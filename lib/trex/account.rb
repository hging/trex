module Trex
  class Account
    attr_reader :key, :secret
    def initialize key,secret
      @key    = key
      @secret = secret
    end
    
    def get_order uuid
      Trex::Order.get(self, uuid)
    rescue 
      nil
    end
    
    def withdraw coin, amt, addr
      Trex.withdraw self.key, self.secret, coin,amt,addr
    end
    
    def withdraw! coin, addr
      Trex.withdraw self.key, self.secret, coin, balance(coin).avail, addr
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
    
    def sell market,amt,rate,&b
      self.class.sell self,market,amt,rate,&b
    end
    
    def self.sell act, market, amt, rate, &b
      if Trex.env[:simulate]
        b.call Order.new({
          "Quantity"     => amt,
          "PricePerUnit" => rate,
          "Price"        => (amt*rate)*0.9975,
          "Closed"       => true,
          "Uuid"         => uuid=Time.now.to_f
        })
        
        return uuid
      else
        uuid = Trex.get({
          key:     act.key,
          secret:  act.secret,
          version: 1.1,
          api:     :market,
          method:  :selllimit,
          query:   {
            quantity: (amt),
            rate:     rate,
            market:   market
          }
        })
        
        Trex::Order.on_fill[uuid] = b if b      
        
        return uuid
      end
    end
    
    def orders market=nil
      Trex.open_orders self.key, self.secret
    end
    
    def address coin
      Trex.address self.key,self.secret,coin.to_s.upcase
    end
    
    def cancel uuid
      Order.get(self, uuid).cancel
    end
    
    def withdrawals coin=nil
      Trex.withdrawal_history self.key,self.secret, coin
    end
    
    Balance = Struct.new(:amount, :avail, :coin, :address, :pending) do
      def btc amount = self.amount
        return 0 if !amount or amount <= 0
        Trex.btc coin,amount
      end
      
      def usd amount = (self.amount ? self.amount : 0)
        return 0 if !amount or amount <= 0
        Trex.usd coin,amount
      end
      
      def rate base=:BTC
        b=base
        c=coin
        
        Trex.btc(coin,1)
      rescue => e
        p e
        0.0
      end
      
      def self.from_obj obj
        ins = new
        
        {"Balance" => :amount, "Available" => :avail, "Currency" => :coin, "Pending" => :pending, "CryptoAddress" => :address}.each_pair do |h,s|
          ins[s] = obj[h]
        end
        ins
      end
    end
    
    def history market: nil, struct: true
      Trex.order_history self.key,self.secret, market: market, struct: struct
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
      self.class::Struct.new key,secret
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
  
  def self.address key,secret,currency
    obj = Trex.get({
      api:     :account,
      version: 1.1,
      method:  :getdepositaddress,
      key:     key,
      secret:  secret,
      query:   {
        currency: currency
      }
    })
    
    return obj["Address"]
  end
  
  Withdrawal = Struct.new(:amount,:address,:txid,:uuid,:cost,:currency,:invalid_addr,:pending,:opened,:cancelled) do
    def self.from_obj obj
      self.new(obj["Amount"],obj["Address"],obj["TxId"],obj["PaymentUuid"],obj["TxCost"],obj["Currency"],obj["InvalidAddress"],obj["PendingPayment"],obj["Opened"],obj["Cancelled"])
    end
  end
  
  def self.withdrawal_history key, secret, coin=nil, struct: true
    obj = Trex.get({
      api:     :account,
      version: 1.1,
      method: :getwithdrawalhistory,
      key:    key,
      secret: secret
    })
    
    return obj unless struct
    
    obj.map do |w|
      Withdrawal.from_obj(w)
    end
  end
  
  def self.withdraw key, secret, coin, amount, address, comment=nil
    obj = Trex.get({
      api:     :account,
      version: 1.1,
      method: :withdraw,
      key:    key,
      secret: secret,
      query:  {
        currency: coin,
        quantity: amount,
        address:  address
      }
    })
  end
end
