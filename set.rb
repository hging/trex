require 'trex'
require 'trex/client'
require 'pry'

class Position
  attr_accessor :client, :type, :market, :order, :rate
  def initialize client, market, type, rate, name: nil
     @market = market
     @type   = type
     @client = client
     @rate   = rate
          
     case type
     when :buy
       @order = client.usd! coin, client.account.balance(:USDT).avail, rate
     when :sell
       @order = client.usd? coin, client.account.balance(coin).avail, rate
     else
       raise
     end
     
     p({
       uuid:   order['uuid'],
       type:   type,
       rate:   rate,
       member: name
     })
     
     raise unless order
  end

  def coin
    market.split("-")[1].to_sym
  end
  
  def closed?
    order and client.order(order['uuid']).closed?
  rescue
  end
end

class Set
  attr_reader :market, :spread, :client, :bits
  attr_accessor :base
  def initialize market, base, spread
    @market = market
    @spread = spread
    @base   = base
  
    @client = Trex::Client.new
    @client.summaries
    
    @bits = [false,false]
  end
  
  def coin
    market.split("-")[1].to_sym
  end
  
  attr_accessor :a, :b
  def init
    @a = Position.new client, market, :buy,  base - (spread*0.5), name: :a
    @b = Position.new client, market, :sell, base + (spread*0.5), name: :b
  
    @bits = [true,true]
  end
  
  def run
    Thread.new do
      loop do
        sleep 3
        poll
      end
    end
  end
  
  def poll
    if a.closed?
      if !bits[0]
        @bits[0] = true
        @a = Position.new client, market, :buy,  base - (spread*0.5), name: :a
      elsif bits[0]
        @bits[0] = false
        @a = Position.new client, market, :sell, base, name: :a
      end
    end
    
    if b.closed?
      if !bits[1]
        @bits[1] = true
        @b = Position.new market, :sell,  base + (spread*0.5), name: :b
      elsif bits[1]
        @bits[1] = false
        @b = Position.new market, :buy, base, name: :b
      end
    end
  end
  
  def enter
    o = client.usd! coin, -0.5, :diff
    until oo = client.order(o['uuid'])
      sleep 1
    end
    
    loop do
      break if oo.closed?
      sleep 1
    end
  end
end


def set market: nil, base: nil, spread: nil
  $set ||= (market ? Set.new(market, base, spread) : nil)
end

Pry.start
