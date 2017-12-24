require 'json'
load "./bin/repl"

Client.repl self

def rapid
  if !@hold
    p [last, ema]
    if last > ema
      return :buy
    end   
  elsif @hold
    if (usd - @last_buy) > 5
      return :sell
    end
  end
  
  :hold
end

def buy
  @hold = true
  @last_buy = base
  @amount   = (base / last)*0.995
end

def sell
  @hold   = false
  @base   = usd
  @amount = 0
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
   
    @base   = 100
    @amount = 0
   
    offset = history.length
    
    @sim_ema = []
   
    for i in 0..offset
      c.get_ema(market, @ema_periods, offset: offset+i) do |ema,err|
        @sim_ema << ema
      end 
    end
    until @sim_ema.length == history.length; 
      Thread.pass
    end
    
    history.each_with_index do |r, i|
      @ema = @sim_ema[i]
      
      analyze(HashObject.becomes({
        last: r
      }))
    end
  end
  
  def on_candle candle, offset: 0
    c.get_ema(market, 2) do |ema, err|
      if !err
        @ema = ema
      else
        raise "#{err}"
      end
    end
  end
  
  def analyze tick
    @last = tick.last
    
    rapid
    
    report tick
  end
  
  def report tick
    print "\r#{ema} #{last} #{base} #{amount}"
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
      
          end
        else
          raise "#{e}"
        end
      end
    end
  end
end

run
while true
  Thread.pass
end
