require 'moving_average'
load "./bin/repl"

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
    @sells += 1
  
    return :hold if (((amount*0.9)*r)*0.9975) < 0.001


    if ARGV.index("-s") or ARGV.index("-S")
      a = amount*0.1
  
      @base += ((amount*0.9)*r)*0.9975    
      @amount = a
    else
      # order!
    end
    
    [:sell, r]
  end

  attr_reader :market
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
      sleep @s ||= 60
      all.shift
      chart.shift
      chart << lr
      all << lr
      ema.shift
      ema << e=all[-(@ema_periods)..-1].ema 
      Thread.pass
    end  
  end

  def init
    @base = 0.03
    @amount = 60
    
    @buys  = 0
    @sells = 0
    
    @lr=chart[0]
    @sc,@sa,@su = [base, amount, (base*18500)+((amount*lr*0.9975)*18500)]
  
    @init = true
  
    if ARGV.index("-s")
      chart.each_with_index do |r,i|
        @e = ema[i]
        
        analyze({
          'last' => @lr=r,
        })
        #sleep 0.111
      end      
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
    p e
  end
  
  def analyze tick
    if o = order?(@lr=tick['last'], e)
      bsh << o if o
    end
    
    report tick
  end
end

run
