require 'json'
load "./bin/repl"

Client.repl self

def rapid
  if !@hold
    if last < ema
      return :buy
    end   
  elsif @hold
    if (usd - @last_buy) > 5#+@loss
      @loss = 0
      return :sell
    elsif (l=(@last_buy - usd)) > 100
      @loss+=l
      return :sell
    end
  end
  
  :hold
end

def buy
  @hold = true
  @last_buy = base
  @amount   = ((base) / last)*0.995
  @sb ||= amount
  @base = 0
  p [:buy, last]
end

def sell
  @hold   = false
  @base   = usd
  @amount = 0
  p [:sell, last]
end

def usd
  amount*last*0.995
end

def hold

end

class << self
  attr_accessor :ema, :ema_periods, :history_periods, :history, :last, :close, :candle, :market, :base, :amount, :last_buy
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
    pp last_tick
    return unless last and ema
    
    @sb ||= base/last
    
    puts "periods: #{@np}"
    puts "#{"%.8f" % @ema} : #{"%.8f" % @last} : #{"%.8f" % b=base+(amount*last)}"
    p [s=(@sb)*last, e=(amount*last)+base, e / s]
  end
  
  def run
    connect

    @history_periods     = (ARGV[1] ||= 60).to_i
    @ema_periods         = (ARGV[2] ||= 12).to_i

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
          
            @amount = 0
            @base   = 100
          
            candles
            
            c.updates do |tick, err|
              if tick.market == market
                @last_tick = tick
                @last      = tick.last
                report
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
