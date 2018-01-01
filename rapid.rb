require 'json'
load "./bin/repl"

Client.repl self

def stash
  @stash += @base - start
  @base = @start
end

def tap
  @base += @stash
  @stash = 0
end

def rapid
  if !@hold
<<<<<<< HEAD
    if last < ema*(1.0-@deviation)
=======
    if last < ema*0.995
>>>>>>> 1f95af6c78766b7bdf1d4e024e121f8921eeb915
      return :buy
    end   
    
  elsif @hold
<<<<<<< HEAD
    if (last >= ema*(1.0+@deviation))
=======
    if (last > ema*1.005)#+@loss
      @loss = 0
      
>>>>>>> 1f95af6c78766b7bdf1d4e024e121f8921eeb915
      return :sell
    end
  end
  
  :hold
end

def profit
  (@lam*last*0.9975)
end

def order type, sim=false
  @log.puts({
    time: Time.now-(@sim_step),
    type: type,
    rate: last,
    balances: {
      base:   base,
      coin:   amount,
      stash:  @stash,
      buried: @buried.avail
    }
  }.to_json)  
  
  if sim
    return
  end
end

def tap
  if sim_order?
    if @stash > 0
      @base += (@stash / base_rate['Last']*0.9975)
      buy
    
      @stash = 0
    end
  end
end

def buy
  @hold = true
  
  if sim_order?
    @last_buy = base*1.0
    @amount   += (@lam=((base*1.0) / last)*0.9975)
    @base = base*0.0
    order :buy, true
  else
    order :buy
  end
  
  @sb ||= ((base) / last)*0.9975

  @buys+=1
  puts
  p [:buy, last]
end

def stash
  if sim_order?
    @stash += ((base-start)*base_rate['Last']*0.9975)
    @base  = start
  end
end

def sell
  @hold   = false
  
  if sim_order?
    @base   += (usd*1.0)
    
    @amount = @amount*0.0
    
    order :sell, true
  else
    order :sell
  end
  
<<<<<<< HEAD
  if base >= (1.2*start)
    stash
  end
  
  if @stash >= start*0.2*base_rate['Last']
    bury
  end     
=======
  if base > (start * 1.1)
    stash    
  end   
>>>>>>> 1f95af6c78766b7bdf1d4e024e121f8921eeb915
  
  @sells+=1
  puts
  p [:sell, last]
end

def bury
  if buried_name
    if sim_order?
      q   = @stash * 0.5
      amt               = (q / buried_rate['Last'])*0.9975
      @buried['avail'] += amt
      @stash            = @stash-q
    end
  end
end


def usd
  amount*last*0.9975
end

def hold
  if usd < (start*0.95)
    tap if (@stash||=0) > 0
  end
end

class << self
  attr_accessor :ema, :ema_periods, :history_periods, :history, :last, :close, :candle, :market, :base, :amount, :last_buy
  def sim_order?
    @simulate or @sim_orders
  end
  
  def simulate
    @simulate = true
   
    @start  = @base = 0.007
    @amount = 0
    @loss   = 0
    
    @buried = HashObject.becomes({
      'avail' => 0
    })
    
    
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
      @sim_step = (history.length-i)*60
      
      (@np ||=0)
       @np += 1
      
      @ema = @sim_ema[i]
      
      @last_tick = HashObject.becomes({
        last: r
      })
      
      @last = r
      
      @hodl ||= (base*0.9975)/r
      
      @start ||= @base+(@amount*r*0.9975)
      
      analyze
    end
  end
  
  def on_candle candle, offset: 0
    @np||=0

    if r=candle.current['close']
      @last = r
    end
    
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
    if @hold and usd <= (start*0.975)
      tap
    end    
    
    send rapid

    report
    #sleep 0.11
  end
  
  def pp o
    puts JSON.pretty_generate(o, allow_nan: true)
  end
  
  attr_reader :last_tick, :start, :hodl
  def report
    return unless last_tick and last and ema
    
    print `clear`
<<<<<<< HEAD
    
    @sb  ||= (base/last)*0.9975
    @sbr ||= base_rate['Last']
    
    puts JSON.pretty_generate({
      buys:       @buys,
      sells:      @sells,
      start:      start,
      hodl:       h=(@sb)*last, 
      total:      e=((amount*last)+base+stash_to_base+buried_to_base),
      usd:        eu=e*base_rate['Last']*0.9975,
      pct_usd:    (eu) / (start*@sbr), 
      coin:       "%.8f" % amount, 
      base:       "%.8f" % base,
      pct:        pct= e/start,
=======

    return unless last and ema
    
    puts JSON.pretty_generate({
      buys:       @buys,
      sells:      @sells,
      start:      @start,
      hodl:       h=(@hodl)*last, 
      total:      e=(amount*last)+base+(@stash||=0),
      coin:       "%.8f" % amount, 
      base:       "%.8f" % base,
      stash:      @stash,
      pct:        e / start,
      vs_hodl:    e / h,
>>>>>>> 1f95af6c78766b7bdf1d4e024e121f8921eeb915
      periods:    @np,
      bid:        last_tick.bid,
      ask:        last_tick.last,
      last:       last,
      ema:        ema,
      target:     {
        buy:  ema*(1.0-@deviation),
        sell: ema*(1.0+@deviation)
      },
      stash:      get_stash,
      buried:     get_buried,
      pppp:       pct/(@np||=0)
    }, allow_nan: true)
  end
  
  def pair
    @pair ||= {
      base: market.split("-")[0],
      coin: market.split("-")[1]
    }
  end
 
  attr_accessor :start
  def run
    @deviation = 0.005 
    @sim_step  = 0
  
    arg = ARGV.find do |a|
      a =~ /\-\-bury\=(.*)/
    end
    
    @log = File.open("orders.log", "w")
    
    if arg
      ARGV.delete(arg)
      @buried_name = $1.upcase
    end
    
    connect
  
    @buys  = @sells = 0
    @stash = 0
   
    @history_periods     = (ARGV[1] ||= 60).to_i
    @ema_periods         = (ARGV[2] ||= 12).to_i

    @sim_orders = (ARGV.index("-s") or ARGV.index("-S"))

    c.subscribe @market=ARGV[0] do |o,e|
      raise "#{e}" if e
      
      c.summary "USDT-#{pair[:base]}" do |br, e|
        @base_rate = br
        c.summary "USDT-#{buried_name.upcase}" do |o, e|
          @buried_rate = o
        
          c.history market, history_periods do |h, e|
            if !e
              @history = h.rates.map do |r| r['close'] end
            
              if ARGV.index('-s')
                Thread.new do
                  simulate
                end
              else
                store.get_ema! :ema, market, ema_periods
              
                c.balances market: market do |b, e|
                  @amount = b.coin['avail']
                  @start  = @base = b.base['avail']
                  
                  c.balance @buried_name.upcase do |b, e|
                    @buried = b
                   
                    candles
                
                    c.updates do |tick, err|
                      store.summary! :buried_rate, "USDT-#{buried_name.upcase}"
                      store.summary! :base_rate,   "USDT-#{pair[:base]}"
                      
                      store.balance!(:buried, buried_name.upcase) unless sim_order?
                      
                      handle_tick tick, err
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
    end
  end
  
  def handle_tick tick, err
    if !err
      if tick.market == market
        @last_tick = tick
        @last      = tick.last
    
        report
      end 
    else
      p err
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
  
  def get_stash
    {
      base:   stash_to_base,
      usd:    @stash,
    }
  end
  
  def get_buried
    return({}) unless @buried_name
  
    {
      name: @buried_name,
      amt:  a=@buried.avail,
      usd:  a*buried_rate['Last'],
      base: buried_to_base
    }
  end
  
  def stash_to_base
    if pair[:base] != "USDT"
      @stash.to_f / base_rate['Last']
    end
  end
  
  def buried_to_base
    a   = @buried.avail
    usd = a*buried_rate['Last']*0.9975  
    usd.to_f / base_rate['Last']*0.9975
  end
  
  attr_reader :buried_rate, :buried_name, :buried, :base_rate
end

run
while true
  Thread.pass
end
