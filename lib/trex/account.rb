module Trex
  class Account
    attr_reader :key, :secret
    def initialize key,secret
      @key    = key
      @secret = secret
    end
    
    def buy market, amt, rate, &b
      if Trex::Opts["sim"]
        b.call Order.new({
          "Quantity"     => (amt*0.9975) / rate,
          "PricePerUnit" => rate,
          "Price"        => amt,
          "Closed"       => true,
          "Uuid"         => Time.now.to_f
        })
      end
    end
    
    def sell market, amt, rate, &b
      if Trex::Opts["sim"]
        b.call Order.new({
          "Quantity"     => amt,
          "PricePerUnit" => rate,
          "Price"        => (amt*rate)*0.9975,
          "Closed"       => true,
          "Uuid"         => Time.now.to_f
        })
      end
    end
    
    def balance coin
    
    end
  end

  class Order
    attr_accessor :uuid, :quantity, :state, :price, :price_per_unit, :type
    def initialize obj
      @quantity = obj["Quantity"]
      @state    = obj["Closed"] ? :closed : :open
      @price    = obj["Price"]
      @uuid     = obj["Uuid"]
      
      @price_per_unit = obj["PricePerUnit"]
    end
    
    def rate
      price_per_unit
    end
    
    def closed?
      state == :closed
    end
  end
end
