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
    
      Balance.new api.account(id)
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
      withdraw addr, amount, type: crypto, currency: coin
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
    
    Balance = Struct.new(*(["id", "currency", "balance", "available", "hold", "profile_id"].map do |k| k.to_sym end)) do
      def self.from_obj acct
        ins = new
        
        acct.keys.each do |k|
          ins[k.to_sym] = acct[k]
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
  
  Order = Struct.new(:id, :price, :size, :product_id, :side, :stp, :type, :time_in_force, :post_only, :created_at, :fill_fees, :filled_size, :executed_value, :status, :settled) do
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
end
