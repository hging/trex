require 'json'
require 'open-uri'
require 'coinbase/exchange'

module GDX
  @env = {}
  def self.env
    @env
  end
  
  def self.env!
    ARGV.find do |a| break if a=~/\-\-account\-file\=(.*)/ end
    if account_file = $1
      env[:account_file] = account_file
      
      obj    = JSON.parse(open(account_file).read)
      key    = obj['gdax']['key']
      secret = obj['gdax']['secret']
      pass   = obj['gdax']['pass']

      env[:account] = GDX::Account.new(key,secret, pass)
    end  
  end
  
  class Account
    attr_accessor :key, :secret, :pass, :api
    def initialize key, secret, pass
      @key    = key
      @secret = secret
      @pass   = pass
      
      @api =  Coinbase::Exchange::Client.new(key, secret, pass)
    
      @product_map = {}
    
      init
    end
    
    def accounts 
      api.accounts
    end
    
    def init
      accounts.each do |b|
        @product_map[b['currency']] = b['id']
      end
    end
    
    def balance sym
      raise "No Symbol: #{sym}" unless id = @product_map[sym.to_s.upcase]
    
      Balance.from_obj api.account(id)
    end
    
    def balances
      accounts.map do |a|
        Balance.from_obj a
      end
    end
    
    def withdraw dest, amount, type: :coinbase, currency: nil
      if type == :coinbase
        api.withdraw dest, amount
      elsif type == :crypto
        params = {}
        
        params[:currency]       = currency
        params[:amount]         = amount
        params[:crypto_address] = dest

        out = nil
        
        api.send(:post, "/withdrawals/crypto", params) do |resp|
          out = api.send(:response_object, resp)
          yield(out, resp) if block_given?
        end
        
        out
      end
    end
    
    def withdraw2addr coin, addr, amount
      withdraw addr, amount, type: :crypto, currency: coin
    end
    
    def coinbase_accounts
      out = nil
      api.send(:get, "/coinbase-accounts") do |resp|
        out = api.send(:response_object, resp)
        yield(out, resp) if block_given?
      end
      out    
    end   
    
    def deposit amount, source, type: :coinbase
    
    end
    
    def orders selector_key = nil, selector_value = nil
      return api.orders if !selector_key
      
      hash = {selector_key => selector_value.to_s} 
      
      api.orders(hash).map do |o|
        Order.from_obj o
      end
    end    
    
    def open_orders
      orders :status, 'open'
    end
    
    def order id
      Order.from_obj api.order(id)
    end
    
    def order_history
      api.fills
    end
    
    def cancel id
      api.cancel id
    end
    
    def sell market, amount, rate
      if !amount or amount == :all
        amount = balance(market.split("-")[0].to_sym)
      elsif amount < 0
        amount = (balance(market.split("-")[0].to_sym).avail * amount.abs)      
      end
    
      m = 2
      m = 5 if market =~ /BTC$/

      p ["%.5f" % amount, "%.#{m}f" % rate]
            
      o = api.sell "%.5f" % amount, "%.#{m}f" % rate, product_id: market, post_only: true
    
      Order.from_obj o      
    end

    def buy market, amount, rate
      if !amount or amount == :all
        amount = balance(market.split("-")[1].to_sym).avail / rate
      elsif amount < 0
        amount = ((v=balance(market.split("-")[1].to_sym)).avail * amount.abs) / rate
      end

      m = 2
      m = 5 if market =~ /BTC$/

      p ["%.5f" % amount, "%.#{m}f" % rate]

      o = api.buy "%.5f" % amount, "%.#{m}f" % rate, product_id: market, post_only: true
    
      Order.from_obj o
    end
    
    Balance = Struct.new(*(["id", "currency", "balance", "available", "hold", "profile_id"].map do |k| k.to_sym end)) do
      def self.from_obj acct
        ins = new
        
        acct.keys.each do |k|
          ins[k.to_sym] = acct.send k
        end
        
        ins
      end
      
      def avail
        available
      end
      
      def amount
        balance
      end
    end
  end 
  
  Order = Struct.new(:id, :price, :size, :product_id, :side, :stp, :type, :time_in_force, :post_only, :created_at, :fill_fees, :filled_size, :executed_value, :status, :settled, :reject_reason, :done_at, :done_reason) do
    def self.from_obj o
      ins = new
       
      o.each_pair do |k,v|
        begin
          ins[k.to_sym] = o.send(k)
        rescue
          ins[k.to_sym] = o[k]
        end
      end
      
      ins
    end
    
    def rate
      price
    end
    
    def quantity
      size
    end
    
    def amount
      size
    end
    
    def total
      size*rate
    end
  end 
  
  env!
  
  p env
  
  class Client
    module SocketAPI
      def tick &b
        @tick_cb = b
      end
      
      def run market, &b
        bool = false
        message do |m|
          b.call m if b

          case m['type']
          when "ticker"
            def m.last; m['price'];    end
            def m.bid;  m['best_bid']; end
            def m.ask;  m['best_ask']; end
            
            @tick_cb.call m if @tick_cb
          when 'snapshot'
           
          end
          
          if !bool
            @socket.send({ type: 'subscribe',product_ids: [market], channels: ['level2', 'heartbeat', {name: 'ticker', product_ids: [market]}] }.to_json)
            bool = true
          end
        end
        
        Thread.new do
          start!
        end
        
        self
      end
    end
    
    attr_accessor :account
    def initialize
      @account = GDX.env[:account]
    end
    Thread.abort_on_exception = true
    def stream market, on_message: nil, &b
      ws = Coinbase::Exchange::Websocket.new(product_id: market)
      ws.extend SocketAPI
      ws.run market, &on_message
      ws.tick &b
      ws    
    end
    
    def balances *o, &b; account.balances(*o, &b); end
    def balance  *o, &b; account.balance *o,&b;    end
    def order id; account.order id; end
    def orders; account.open_orders; end
    
    def usd? coin, amount=nil, rate=nil
      account.sell "#{coin}-USD".upcase, amount, rate
    end
    
    def usd! coin, amount=nil, rate=nil
      account.buy "#{coin}-USD".upcase, amount, rate
    end    
    
    def cancel id
      account.cancel id
    end
    
    def cancel_all
      orders.map do |o|
        cancel o.id
      end
    end
    
    def last coin, base: :USD, rate: :last
      if coin.is_a? String
        base, coin = coin.split("-")
      end
      
      t = account.api.last_trade product_id: "#{coin}-#{base}"
    
      rate = :price if rate == :last
    
      t.send(rate).to_f
    end
  end
end
