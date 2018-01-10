require 'trex'
$: << File.join(File.dirname(__FILE__), 'lib')
require 'pry'
require 'trex/client'

class << self
  def run
    base  = 0
    amt   = 0.0741839
    pos   = :sell
    start = 1290
    pct   = 0.005
    sells = 0
    buys  = 0

    client.stream "USDT-ETH" do |b,*o| 
      if pos == :sell and b.bid >= target=(start*(1+pct))
        pos   = :buy
        base += amt*b.bid*0.9975
        amt   = 0
        sleep 1
      
        sells += 1
      elsif pos == :buy and b.ask <= target=(start*(1-pct))
        pos = :sell
        base = 0
        amt = ((base*0.9975)/b.ask)
        sleep 1
       
        buys += 1
      end

      print `clear`
      puts JSON.pretty_generate({
        usd:    (amt*(r=b.last)+base),
        rate:   b.last,
        bid:    b.bid,
        ask:    b.ask,
        target: target,
        sells:  sells,
        buys:   buys
      }) 
    end
  end
  
  def client
    @client = Trex::Client.new
  end
end

run

Pry.start
