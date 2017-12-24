require 'json'
load "./bin/repl"

Client.repl self

def rapid
  if !@hold
    if last < ema
      return :buy
    end   
    
  elsif @hold
    if (profit / @last_buy) > 1.01#+@loss
      @loss = 0
      return :sell
    
    elsif (l=(@last_buy - profit)) > 100
      @loss+=l
      return :sell
    end
  end
  
  :hold
end

def profit
  (@lam*last*0.9975)
end

def order type

end

def buy
  @hold = true
  
  if sim_order?
    @last_buy = base*1.0
    @amount   += (@lam=((base*1.0) / last)*0.9975)
    @base = base*0.0
  else
    order :buy
  end
  
  @sb ||= ((base) / last)*0.9975

  @buys+=1
  puts
  p [:buy, last]
end

def sell
  @hold   = false
  
  if sim_order?
    @base   += (usd*1.0)
    @amount = @amount*0.0
  else
    order :sell
  end
  
  @sells+=1
  puts
  p [:sell, last]
end

def usd
  amount*last*0.9975
end

def hold

end

class << self
  attr_accessor :ema, :ema_periods, :history_periods, :history, :last, :close, :candle, :market, :base, :amount, :last_buy
  def sim_order?
    @simulate or @sim_orders
  end
  
  def simulate
    @simulate = true
   
    @base   = 500
    
    @amount = 0
    @loss   = 0
    
    offset = history.length
    
    @sim_ema = []
   
    for i in 0..offset-1
      c.get_ema(market, @ema_periods, offset: offset-i) do |ema,err|
        @sim_ema << ema
      end 
    end
    
    until @sim_ema.length == history.length; 
      Thread.pass
    end
    
    history.each_with_index do |r, i|
      (@np ||=0)
       @np += 1
      
      @ema = @sim_ema[i]
      
      @last_tick = HashObject.becomes({
        last: r
      })
      
      @last = r
      
      analyze
    end
  end
  
  def on_candle candle, offset: 0
    @np||=0
    
    c.get_ema(market, ema_periods) do |ema, err|
      puts "periods: #{@np+=1}"
      if !err
        @ema = ema
     
        analyze
      else
        raise "#{err}"
      end
    end
  end
  
  def analyze    
    send rapid
    report
    #sleep 0.11
  end
  
  def pp o
    puts JSON.pretty_generate(o, allow_nan: true)
  end
  
  attr_reader :last_tick
  def report
    return unless last_tick
    print `clear`
    puts "["
    pp last_tick
    puts ","
    return unless last and ema
    
    @sb ||= base/last
    
    puts JSON.pretty_generate({
      buys:       @buys,
      sells:      @sells,
      hodl:       s=(@sb)*last, 
      base_value: e=(amount*last)+base,
      coin:       "%.8f" % amount, 
      base:       "%.8f" % base,
      pct:        e / s,
      periods:    @np,
      bid:        last_tick.bid,
      ask:        last_tick.last,
      last:       last,
      ema:        ema
    }, allow_nan: true)
    puts "]"
  end
  
  def run
    connect
  
    @buys = @sells = 0

    @history_periods     = (ARGV[1] ||= 60).to_i
    @ema_periods         = (ARGV[2] ||= 12).to_i

    @sim_orders = (ARGV.index("-s") or ARGV.index("-S"))

    c.subscribe @market=ARGV[0] do |o,e|
      raise "#{e}" if e
      
      c.history market, history_periods do |h, e|
        if !e
          @history = h.rates.map do |r| r['close'] end
        
          if ARGV.index('-s')
            Thread.new do
              simulate
            end
          else
            store.get_ema :ema, market, ema_periods
          
            c.balances market: market do |b, e|
              @amount = b.coin['avail']
              @base   = b.base['avail']
          
              candles
            
              c.updates do |tick, err|
                if tick.market == market
                  @last_tick = tick
                  @last      = tick.last
                  
                  report
                end
              end
            end
          end
        else
          raise "#{e}"
        end
      end
    end
  end
  
  def candles
    c.next_candle market do |candle, err|
      if !err
        on_candle candle
      else
        p err
      end
    
      candles
    end  
  end
end

run
while true
  Thread.pass
end
