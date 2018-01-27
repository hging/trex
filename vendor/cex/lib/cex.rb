module CEX
  require 'open-uri'
  require 'json'
  require 'openssl'

require "openssl"
require "net/http"
require "net/https"
require "uri"
require "json"
require "addressable/uri"

  @env = {}
  def self.env
    @env
  end
  
  def self.env!
    ARGV.find do |a| break if a=~/\-\-account\-file\=(.*)/ end
    if account_file = $1
      env[:account_file] = account_file
      
      obj    = JSON.parse(open(account_file).read)
      key    = obj['cex']['key']
      secret = obj['cex']['secret']

      env[:account] = CEX::Account.new(key,secret)
    end  
  end
  
  class API
    attr_accessor :api_key, :api_secret, :username, :nonce_v
  
    def initialize(username, api_key, api_secret)
      self.username = username
      self.api_key = api_key
      self.api_secret = api_secret
    end
  
    def api_call(method, param = {}, priv = false, action = '', is_json = true)
      url = "https://cex.io/api/#{ method }/#{ action }"
      if priv
        self.nonce
        param.merge!(:key => self.api_key, :signature => self.signature.to_s, :nonce => self.nonce_v)
      end
      p url, param
      answer = self.post(url, param)
  
      # unfortunately, the API does not always respond with JSON, so we must only
      # parse as JSON if is_json is true.
      if is_json
        JSON.parse(answer)
      else
        answer
      end
    end
  
    def ticker(couple = 'USD/BTC')
      self.api_call('ticker', {}, false, couple)
    end

    def convert(couple = 'USD/BTC', amount = 1)
      self.api_call('convert', {:amnt => amount}, false, couple)
    end

    def order_book(couple = 'USD/BTC')
      self.api_call('order_book', {}, false, couple)
    end
  
    def trade_history(since = 1, couple = 'USD/BTC')
      self.api_call('trade_history', {:since => since.to_s}, false, couple)
    end
  
    def balance
      self.api_call('balance', {}, true)
    end
  
    def open_orders(couple = 'USD/BTC')
      self.api_call('open_orders', {}, true, couple)
    end
  
    def cancel_order(order_id)
      self.api_call('cancel_order', {:id => order_id.to_s}, true, '',false)
    end
  
    def place_order(ptype = 'buy', amount = 1, price =1, couple = 'USD/BTC')
      self.api_call('place_order', {:type => ptype, :amount => amount.to_s, :price => price.to_s}, true, couple)
    end

    def archived_orders(couple = 'USD/BTC', options = {})
      self.api_call('archived_orders', options, true, couple)
    end

    def get_order(order_id)
      self.api_call('get_order', {:id => order_id.to_s}, true, '',true)
    end

    def get_order_tx(order_id)
      self.api_call('get_order_tx', {:id => order_id.to_s}, true, '',true)
    end

    def get_address(currency)
      self.api_call('get_address', {:currency => currency}, true, '',true)
    end

    def get_myfee
      self.api_call('get_myfee', {}, true, '',true)
    end
  
    def hashrate
      self.api_call('ghash.io', {}, true, 'hashrate')
    end
  
    def workers_hashrate
      self.api_call('ghash.io', {}, true, 'workers')
    end
  
    def nonce
      self.nonce_v = (Time.now.to_f * 1000000).to_i.to_s
    end
  
    def signature
      str = self.nonce_v + "up109059129".to_s + self.api_key
      OpenSSL::HMAC.hexdigest(OpenSSL::Digest::Digest.new('sha256'), self.api_secret, str)
    end
  
    def post(url, param)
      uri = URI.parse(url)
      https = Net::HTTP.new(uri.host, uri.port)
      https.use_ssl = true
      params = Addressable::URI.new
      params.query_values = param
      https.post(uri.path, params.query).body
    end
  end  

  class Account
    attr_reader :key, :secret, :api
    def initialize key,secret
      @key    = key
      @secret = secret
      
      @api = API.new nil, key,secret
    end
  end

  env!
  
  class Client
    attr_reader :account
    def initialize
      @account = CEX::env[:account]
    end
    
    def last coin, base: :USD
      o = symbol_params :last_price, coin, base
      o.lprice.to_f
    end
    
    def symbol_params m, *coins
      resp = open("https://cex.io/api/#{m}/#{coins.join("/")}").read
      o = JSON.parse resp

      HashObject.becomes o
    end
    
    module HashObject
      def self.becomes o
        return o unless o.respond_to?(:"[]")
        
        return o if o.is_a?(String)
        
        return o if o.is_a?(Symbol)
        
        o.extend self
        
        (o = o[:result] || o) if o.is_a?(self) and !o.is_a?(Array) and !o.is_a?(Struct)
        
        o
      rescue
        o
      end
      
      def [] k
        r = super(k)
        HashObject.becomes r if r
      end
      
      def method_missing m,*o
        return super if is_a?(String)
        
        if r=self[m.to_sym] or r=self[m.to_s] or self[cc=m.to_s.split("_").map do |q| q.capitalize end.join.to_sym] or self[cc]
        elsif is_a?(Hash)
          r=super unless keys.index(m.to_sym) or keys.index(m.to_s) or keys.index(cc) or keys.index(cc.to_sym)
        elsif is_a?(Struct)
          r=super unless members.index(m.to_sym) or members.index(cc) or members.index(cc.to_sym)
        end
        
        r
      end
    end
  
    def result o
      HashObject.becomes o
    end
    
    Tick = Struct.new :last,:bid,:ask
    
    class WSCat
      require 'open3'
      Thread.abort_on_exception = true
      attr_reader :t, :i, :o, :e
      def initialize
        @t = Thread.new do
          Open3.popen3 "wscat -c wss://ws.cex.io/ws/" do |i,o,e,_|
            @i = i
            @o = o
            @e = e
            
            loop do
              m= (o.gets || e.gets)
              message! m if m
            end  
          end
        end
      end
      
      def message! m
        m = m.gsub(">",'').strip
        @message.call HashObject.becomes(JSON.parse(m)) if @message
      end
      
      def message &b
        @message = b
      end
      
      def puts m
        STDOUT::puts "> #{m}"
        @i.puts m;
      end
    end
    
    attr_reader :ws, :ws_markets
    def stream market = nil, message: nil, modify: nil, connect: nil, &b
      coin, base = market.split("-")
    
      if !ws_markets
        @ws_markets = {}
      end
    
      if !ws
        @ws = WSCat.new
        until ws.i; end
      end
      
      ws.message do |m|
        message.call m if message
      
        case m.e
        when 'connected'
          connect.call if connect
        
          ws.puts ({"e": "subscribe","rooms": ["tickers"]}).to_json
          ws.puts ({"e": "subscribe","rooms": ["pair-#{coin}-#{base}"]}).to_json if market
        when 'tick'
          market_ = "#{m.data.symbol1}-#{m.data.symbol2}"
          tick = (@ws_markets[market] ||= Tick.new nil,nil,nil)
          tick.last = m.data.price.to_f
        
          b.call(tick, market_) if (market == market_) or (!market)
        when 'md'
          market = m.data.pair.gsub(":", "-")
          tick = (@ws_markets[market] ||= Tick.new nil,nil,nil)
          tick.ask = m.data.sell[0][0]
          tick.bid = m.data.buy[0][0]
        
          modify.call market, tick if modify
        else
        end
      end
    end
  end
end
