module Trex
  class JSONApi
    require 'json'
    require 'open-uri'

    require 'base64'
    require 'cgi'
    require 'openssl'

    @req=-1
    @s = nil
    @rpm  = nil
    def self.fetch url, header: {}
      @s = Time.now if @req < 0
      @req+=1
      
      puts "\nURL: #{url}" if Trex.env[:debug]
      
      res = JSON.parse open(url, header).read
      
      return res["result"] if res["success"]
      
      raise "#{res["message"]}"
    end
    
    def self.rate
      secs = Time.now - @s
      mins = secs / 60.0
      
      @rpm = (@req/mins) / 60.0
    end
    
    def self.fetch_signed url, key, secret
      url = url + "&nonce=#{Time.now.to_f.to_s.gsub(".",'')}&apikey=#{key}"
      fetch url, header: {'apisign' => sign(url, secret)}
    end
    
    def self.sign data,secret
      digest = OpenSSL::Digest.new('sha512')

      OpenSSL::HMAC.hexdigest(digest, secret, data)
    end
  end
  
  def self.get obj, &b
    version = obj[:version] ||= 1.1
    api     = obj[:api]
    method  = obj[:method]
    query   = obj[:query] ||= {}
    
    query_str = []
    query_str = query.map do |k,v|
      query_str << "#{k}=#{v}"
    end.join("&")
    
    query_str = " " if query_str == "" and (api.to_sym == :market or api.to_sym == :account)
    
    uri = "https://bittrex.com/api/v#{version}/#{api}/#{method}#{query_str.empty? ? "" : "?"}#{query_str}".strip
    
    case api    
    when :public
      JSONApi.fetch uri
    when :pub
      JSONApi.fetch uri
    when :market
      JSONApi.fetch_signed uri, obj[:key], obj[:secret]
    when :account
      JSONApi.fetch_signed uri, obj[:key], obj[:secret]
    else
      raise "Unknown API #{api}"
    end
  end
    
  module Market
    Tick = Struct.new(:high,:low,:open,:close, :btc_volume, :volume) do
      def self.from_obj obj
        ins = new
        
        {"H" => :high, "L"=>:low, "O"=>:open, "C"=>:close, "BV"=>:btc_volume, "V"=>:volume}.map do |h,s|
          ins[s] = obj[h]
        end
        
        return ins
      end
    end
    
    def self.ticks market, interval=:oneMin, struct: true
      obj = Trex.get({
        api:    :pub,
        method: 'market/GetTicks',
        version: 2.0,
        query: {
          marketName:     market,
          tickInterval:   interval
        }
      })
      
      return obj unless struct
      
      obj.map do |t|
        Tick.from_obj t
      end
    end
    
    Ticker = Struct.new(:bid, :ask, :last) do
      def self.from_obj o
        ins = new(o["Bid"], o["Ask"], o["Last"])
      end
      
      def self.for market
        Trex::Market.ticker(market)
      end
      
      def pp
        "B:#{bid} A:#{ask} L:#{last}"
      end
    end
    
    def self.ticker market, struct: true
      obj = Trex.get({
        api:     :public,
        method:  :getticker,
        version: 1.1,
        query: {
          market: market
        }
      })
      
      obj[:MarketName] = market
      obj[:Last]       = obj["Last"]
      obj[:Ask]        = obj["Ask"]
      obj[:Bid]        = obj["Bid"]
                  
      Trex.update_candle obj # unless Trex.env[:streaming_rates]
      
      return obj unless struct
      
      Ticker.from_obj obj
    end
    
    module Summary
      def self.from_obj obj
        obj.extend self
      end
      
      [:market_name, :volume, :prev_day, :open, :close, :high, :low, :last, :base_volume, :bid, :ask].each do |k|
        define_method k do
          self[k.to_s.split("_").map do |c| c.capitalize end.join]
        end
      end
    end
    
    def self.summaries struct: true
      obj = Trex.get({
        method:  :getmarketsummaries,
        version: 1.1,
        api:     :public
      })
      
      obj.each do |o|
        (Trex.env[:rates] ||= {})[market] = o["Last"] unless Trex.env[:streaming_rates]
      end
      
      return obj unless struct
      
      obj.map do |o|
        Summary.from_obj o
      end
    end
    
    def self.summary market, struct: true
      obj = Trex.get({
        method:  :getmarketsummary,
        version: 1.1,
        api:     :public,
        query: {
          market: market
        }
      })
      
      (Trex.env[:rates] ||= {})[market] = obj["Last"] unless Trex.env[:streaming_rates]
      
      return obj unless struct
      
      Summary.from_obj obj
    end 
    
    def self.book market, type
      obj = Trex.get({
        version: 1.1,
        method:  :getorderbook,
        api:     :public,
        query:   {
          market: market,
          type:   type
        }   
      })
      
      return obj
    end   
  end
  
  Order = Struct.new(:uuid, :quantity, :state, :price, :price_per_unit, :type, :account, :market,:limit) do    
    def marshal_dump
      if account
        cpy         = clone
        cpy.account = nil
        cpy.marshal
      else
        super
      end 
    end
  
    def self.from_obj obj, account: nil
      ins = new
      
      ins.quantity = obj["Quantity"]
      ins.state    = obj["Closed"] ? :closed : :open
      ins.price    = obj["Price"]
      ins.uuid     = obj["OrderUuid"]
      ins.market   = obj["Exchange"]
      ins.type     = obj["OrderType"]
      ins.limit    = obj["Limit"]
      ins.account  = account.to_struct
      
      ins.price_per_unit = obj["PricePerUnit"]
    
      ins
    end
    
    def self.on_fill
      @on_fill ||= {}
    end
    
    def events!
      if @on_fill and closed?
        @on_fill.call self
        self.class.on_fill.delete uuid
      end
    end
    
    def on_fill &b
      self.class.on_fill[uuid] = b
    end
    
    def rate
      price_per_unit
    end
    
    def closed?
      state == :closed
    end
    
    def cancel
      self.class.cancel self.account, self.uuid
    end
    
    def canceled?
      !price and closed?
    end
    
    def pp
      h = self.to_h
      h.delete :account
      h.keys.each do |k|
        if h[k].is_a?(Float)
          h[k] = h[k].trex_s(10)
        end
      end
      JSON.pretty_generate h
    end
    
    def self.history account, struct: true
      obj = Trex.get({
        
      })
      
      return obj unless struct
      
      obj.map do |o|
        from_obj account,o
      end
    end
    
    def self.get_open account, struct: true
      obj = Trex.get({
        version: 1.1,
        method:  :getopenorders,
        api:     :market,
        key:     account.key,
        secret:  account.secret   
      })
      
      return obj unless struct
      
      obj.map do |o|
        from_obj o, account: account
      end
    end
  
    def self.cancel account, uuid
      Trex.get({
        key:     account.key,
        secret:  account.secret,
        method:  :cancel,
        version: 1.1,
        api:     :market,
        query:   {
          uuid: uuid,
        }
      })
      
      true
    end
  
    def self.get account, uuid, struct: true
      obj = Trex.get({
        version: 1.1,
        api:    :account,
        method: :getorder,
        key:    account.key,
        secret: account.secret,
        query: {
          uuid: uuid
        }
      })
      
      return obj unless struct
      
      from_obj obj, account: account
    rescue => e
      raise e
    end
    
    def self.history account, market: nil, struct: true
      q = {}
      q = {
        market: market
      } if market
       
      obj = Trex.get({
        version: 1.1,
        api:    :account,
        method: :getorderhistory,
        key:    account.key,
        secret: account.secret,
        query: q
      })
      
      return obj unless struct
      
      obj.map do |o|
        from_obj o, account: account
      end
    end    
  end  
  
  def self.account key,secret, struct: false
    return Account.new(key,secret) unless struct
    
    Account::Struct.new(key, secret)
  end
  
  def self.open_orders key, secret, struct: true
    Order.get_open(account(key,secret, struct: true), struct: struct)
  end
  
  def self.order_history key, secret, market: nil, struct: true
    Order.history(account(key,secret, struct: true), market: market, struct: struct)
  end
  
  def self.order key, secret, uuid, struct: true
    Order.get(account(key,secret, true), uuid, struct: struct)
  end
  
  def self.cancel key, secret, uuid
    Order.cancel(account(key,secret, true), uuid)
  end
  
  def self.buy key, secret, market, amount, rate
    Account.buy account(key, secret), market, amount, rate
  end
  
  def self.summaries struct: true
    Market.summaries struct: struct
  end
  
  def self.get_ticks market, interval=:oneMin, struct: true
    Market.ticks market, interval, struct: struct
  end
  
  def self.ticker market, struct: true
    Market.ticker market, struct: struct
  end  
  
  def self.book market, type
    Market.book market, type
  end
end

if __FILE__ == $0
  require "trex"
  
  # raw ticks
  obj = Trex.get({
    api:    :pub,
    method: 'market/GetTicks',
    version: 2.0,
    query: {
      marketName: "BTC-CVC",
      tickInterval:   :oneMin
    }
  })
  
  Trex::Market.ticks("BTC-CVC")
  
  Trex::Market::Ticker.for("BTC-CVC")
  Trex::Market.ticker "BTC-CVC"
  
  p Trex.env[:rates]
end
