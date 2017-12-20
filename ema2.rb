require 'moving_average'
load "./bin/repl"
require 'googlecharts'
module Enumerable
  def every(n)
    (n - 1).step(self.size - 1, n).map { |i| self[i] }
  end
end
class << self
  attr_reader :ema, :chart, :sc,:sa,:su, :ea,:ec,:eu, :bsh, :all, :lr, :base, :amount, :e

  def order? r,e
    if r < e*0.995
      send (ARGV.index("-r") ? :sell : :buy), r
    elsif r > e*1.005
      send (ARGV.index("-r") ? :buy : :sell), r
    else
    end
  end

  def buy r
    return :hold if (base*0.5) < 0.001
    
    @period_did_act = true
    @buys += 1
    
    if ARGV.index("-s") or ARGV.index("-S")
      @amount += ((base*0.5)/r)*0.9975
      @base = base*0.5
    else
      # order!
    end
    [:buy, r]
  end

  def sell r  
    return :hold if (((amount*0.9)*r)*0.9975) < 0.001

    @sells += 1
    @period_did_act = true
          
    if ARGV.index("-s") or ARGV.index("-S")
      a = amount*0.1
  
      @base += ((amount*0.9)*r)*0.9975    
      @amount = a
    else
      # order!
    end
    
    [:sell, r]
  end

  attr_reader :market, :usd
  def run
    raise "No Market" unless @market = ARGV[0]
    
    ARGV[1] ||= 105
  
    Client.repl self
    @ema_periods = ARGV[2].to_i ||= 12
    connect
  
    c.subscribe market do
      c.history market, ARGV[1].to_i do |h|
   
        @all   = h['result']['rates'].map do |c| c['close'] end
        @chart = all[(@ema_periods-1)..-1]
        @bsh   = []
        @ema   = []
        offset = 0
        
        chart.each do |r|
          rng=offset..(offset+@ema_periods)
          ema << @e=all[rng].ema
          offset += 1
        end
        
        init
      end
    end
    
    main
  end
  
  def main
    until @init; end
    
    while true
      Thread.pass
    end  
  end

  def init
    @base = 0.03
    @amount = 60
    
    @buys  = 0
    @sells = 0
    @usd   = []
    @lr=chart[0]
    @sc,@sa,@su = [base, amount, (base*18500)+((amount*lr*0.9975)*18500)]
  
    @init = true
  
    if ARGV.index("-s")
      chart.each_with_index do |r,i|
        e = ema[i]
        
        on_candle({
            'current' => {
              'close'  => r,
              'ema'    => ema[i]=all[i..i+11].ema
            },
            
            'last' => {
              'close' => (i > 0 ? chart[i-1] : nil),
              'ema'   => (i > 0 ? ema[i-1] : nil)
            }
        })
        
        analyze({
          'last' => r,
        })
        #sleep 0.111
      end      
      puts render
    else
      c.updates do |tick|
        if !tick['err']
          analyze tick['result'] if tick['result']['market'] == market
        end
      end
    end
  end

  def report tick
    print `clear`
    puts JSON.pretty_generate(tick, allow_nan: true)
    p [sc,sa,su]
    p [@ec=base, @ea=amount, @eu=(base*18500)+((amount*lr*0.9975)*18500)]
    p [ec/sc, ea/sa, eu/su]
    p [lr, e]
    p "Sells: #{@sells} Buys: #{@buys}"
  end
  
  def period_did_act?
    (@period == @last_period) and @period_did_act
  end
  
  def on_candle c, shift=false
    @last_period = @period ||=0
    @period += 1
    @period_did_act = false
  
    @e      = c['current']['ema']
    @candle = c
    
    usd     << @eu=(base*18500)+((amount*lr*0.9975)*18500)
    
    if shift
      usd.shift
      ema.shift
      chart.shift
      chart   << c['current']['close']
    end
    
    c
  end
  
  def render
require 'gruff'
g = Gruff::Line.new

g.title = 'Wow!  Look at this!'

g.data :ema12, ema.map do |q| q*1000 end
g.data :price, chart.map do |q| q*1000 end

g.write('exciting.png')
  end
  
  def analyze tick

    if !period_did_act?
      if o = order?(@lr=tick['last'], e)
        bsh << o if o
      end
    end
    report tick
  p [@last_period, @period, @period_did_act, e, @lr]
  end
end

run
