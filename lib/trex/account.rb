module Trex
  class Account
    attr_reader :key, :secret
    def initialize key,secret
      @key    = key
      @secret = secret
    end
    
    def buy market, amt, rate, &b
      self.class.buy self, market,amt, rate,&b
    end
    
    def self.buy act, market,amt, rate,&b
      uuid = nil
      
      if Trex.env[:simulate]
        uuid  = Time.now.to_f
        order = Order.new({
          "Quantity"     => (amt*0.9975) / rate,
          "PricePerUnit" => rate,
          "Price"        => amt,
          "Closed"       => true,
          "Uuid"         => uuid
        })
        
        b.call order if b
      else
        uuid = Trex.get({
          key:     act.key,
          secret:  act.secret,
          version: 1.1,
          api:     :market,
          method:  :buylimit,
          query:   {
            quantity: (amt*0.9975)/rate,
            rate:     rate,
            market:   market
          }
        })
        
        Trex::Order.on_fill[uuid] = b if b
      end
      
      return uuid    
    end
    
    def sell market, amt, rate, &b
      if Trex.env[:simulate]
        b.call Order.new({
          "Quantity"     => amt,
          "PricePerUnit" => rate,
          "Price"        => (amt*rate)*0.9975,
          "Closed"       => true,
          "Uuid"         => Time.now.to_f
        })
      end
    end
    
    def cancel uuid
      Order.get(self, uuid).cancel
    end
    
    Balance = Struct.new(:amount, :avail, :coin, :address, :pending) do
      def btc amount = self.amount
        Trex.btc coin,amount
      end
      
      def usd amount = self.amount
        Trex.usd coin,amount
      end
      
      def self.from_obj obj
        ins = new
        
        {"Balance" => :amount, "Available" => :avail, "Currency" => :coin, "Pending" => :pending, "CryptoAddress" => :address}.each_pair do |h,s|
          ins[s] = obj[h]
        end
        ins
      end
    end
    
    def balance coin, struct: true
      obj = Trex.get({
        api:     :account,
        version: 1.1,
        method:  :getbalance,
        key:     key,
        secret:  secret,
        query:   {
          currency: coin.to_s.upcase
        }
      })
      
      return obj unless struct
      
      Balance.from_obj obj
    end
    
    def balances struct: true
      obj = Trex.get({
        api:     :account,
        version: 1.1,
        method:  :getbalances,
        key:     key,
        secret:  secret      
      })
      
      return obj unless struct
      
      obj.map do |b|
        Balance.from_obj b
      end
    end
    
    def to_struct
      self.class.Struct.new key,secret
    end
    
    self::Struct = ::Struct.new(:key, :secret) do
      def to_act
        Trex::Account.new(key, secret)
      end
      
      def to_struct
        self
      end
    end
  end
end
