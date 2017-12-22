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

  def reverse_ema r, e
    return unless r and e
    if r < e*0.995
      send (ARGV.index("-r") ? :sell : :buy), r
    elsif r > e*1.005
      send (ARGV.index("-r") ? :buy : :sell), r
    else
    end  
  end
  
  def rapid r, e
    if @hold
      if r > @last_buy*1.003
        if (q=sell(r)) != :hold
          @last_sell = r
          q
        end
      end
    else
      if @last_sell
        if r < @last_sell*0.997
          if (q = buy(r)) != :hold
            @last_buy = r
            q
          end
        end
      else
        if (q = buy(r=0.00000328)) != :hold
          @last_buy = r
          q
        end
      end
    end
  end

  def order? r,e
    send @strategy, r, e
  end

  def buy r
    return :hold if (base*0.5) < 0.001
    return :hold if @hold
    @period_did_act = true
    @buys += 1
    @hold = true
    if ARGV.index("-s") or ARGV.index("-S")
      @amount += ((base*0.5)/r)*0.9975
      @base = base*0.5
    else
      # order!
    end
    [:buy, r]
  end

  def sell r
    return :hold unless @hold  
    return :hold if (((amount*0.9)*r)*0.9975) < 0.001

    @sells += 1
    @period_did_act = true
    @hold = false      
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
  
    if !@btc_r
      c.tick "USDT-BTC" do |tick, err|
        if !err
          @btc_r = tick['last']
        end
      end
    end
  
    until @btc_r; end
  
    c.subscribe market do
      c.history market, ARGV[1].to_i+(ep=ARGV[2].to_i) do |h|
        @history = h['rates'][0..-1].map do |c| c['close'] end
        @chart = h['rates'][ep-1..-1].map do |c| c['close'] end
        @ema   = []
        @bsh   = []
        
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
    @strategy = :reverse_ema
    @base   = 0.03
    @amount = 0.19
    
    @buys  = 0
    @sells = 0
    @usd   = []
    @lr=chart[0]
    @sc,@sa,@su = [base, amount, (base*@btc_r)+((amount*lr*0.9975)*@btc_r)]
  
    @init = true
       
         
    if ARGV.index("-s")
      @sr = chart[0]     
    end
        
    chart.each_with_index do |r,i|
      @ema << @e=@history[i..i+ARGV[2].to_i].ema
      
      if ARGV.index("-s") 
        on_candle({
            'current' => {
              'close'  => r,
              'ema'    => e
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
    end
    
    if !ARGV.index("-s")
      @lr = chart[-1]  
      
      c.updates do |tick, err|
        if !err
          analyze tick      if tick['market'] == market
          set_btc_rate tick if tick['market'] == "USDT-BTC"
        end
      end
      
      listen_candle
    else
      puts render
    end
  end
  
  def listen_candle
    c.next_candle market do |candle, err|
      if !err
        c.get_ema market, ARGV[2].to_i do |ema, err| 
          if !err
            @e = ema
            on_candle(candle, true)
          end
        end
      end
      
      listen_candle
    end  
  end
  
  def set_btc_rate tick
    @btc_r = tick['last']
    report @lt if @lt
  end

  def report tick
    return unless @lr
  
    @lt = tick
    print `clear`

    puts JSON.pretty_generate({
      tick: tick,
      start: {
        rate: @sr,
        base: sc,
        coin: sa,
        usd:  su
      },
      current: {
        base: {
          amount:  @ec=base,
          percent: (ec/sc),
        },
        coin: {
          amount:  @ea=amount, 
          percent: (ea/sa),
        },
        usd: {
          amount:  @eu=(base*@btc_r)+((amount*lr*0.9975)*@btc_r),
          percent: (eu/su)
        },
        ema: {
          current: @e,
          sell:    @e*1.005,
          buy:     @e*0.995
        }
      },
      buys:    @buys,
      sells:   @sells,
      periods: @period,
      if_hodled: {
        usd:     hu=(sc*@btc_r)+((sa*lr*0.9975)*@btc_r),
        percent: (hu/su)
      }
    }, allow_nan: true)
  end
  
  def period_did_act?
    (@period == @last_period) and @period_did_act
  end
  
  def on_candle c, shift=false
    @last_period = @period ||=0
    @period += 1
    @period_did_act = false
  
    
    usd     << @eu=(base*@btc_r)+((amount*lr*0.9975)*@btc_r)
    
    if shift
      usd.shift
      ema.shift
      chart.shift
      chart   << c['current']['close']
    end
    
    c
  end
  
  require 'gruff'
  require 'base64'  
  def render
    g = Gruff::Line.new('1000x800')
    g.line_width = 1
    g.dot_radius = 1
    g.left_margin = 0
    
    g.theme = {
      :colors => [
        '#FFF804',  # yellow
        '#336699',  # blue
        'black',  # green
        '#ff0000',  # red
        '#cc99cc',  # purple
        '#cf5910',  # orange
        'black'
      ],
      :marker_color => 'black',
      :font_color => 'black',
      :background_colors => %w(white white)
    }
    
    g.title = market

    g.data :ema, ema
    g.data :sell, (ema.map do |q| q*1.005 end)
    g.data :buy, (ema.map do |q| q*0.995 end)
    g.data :price, chart

    g.write("#{market}.png")
    Base64.encode64(open("#{market}.png").read)
    true
  end
  
  def analyze tick
    @sr ||= tick['last']
    
    if !(tick['last'] == @lr)#!period_did_act?
      if o = order?(@lr=tick['last'], e)
        bsh << o if o
      end
    end
    report tick
  end
end

run
