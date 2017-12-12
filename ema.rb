require 'moving_average'

require 'trex'

class ChartBuffer
  def initialize base, coin
    @base = base
    @coin = coin
  end

  def signal a,b
    res = a <=> b
    
    return  0 if res == 0
    return  -1 if a > b
    return   1 if a < b
    
    return 0
  end
  
  def sim hours, &b
    @all = Trex.get_ticks("#{@base}-#{@coin}")[-((60*(hours))+26)..-1].map do |q| q.close end

   # (hours/1.5).floor.times do
      @period = @all[45..(((hours)*60)+26)].find_all do |q| q end   
      b.call
      @all.shift
   # end
    
   # b.call
  end

  def sell?
    @sell
  end
  
  attr_accessor :sell

  def update
    if !@period
      @period     = Trex.get_ticks("#{@base}-#{@coin}")[-((46*1)+26)..-1].map do |q| q.close end
      @period[-1] = Trex.candle("#{@base}-#{@coin}").diff if !ARGV.index("-s")
    end
  
    if !ARGV.index("-s")
      @period.shift 
  
      candle = Trex.candle("#{@base}-#{@coin}")
      @period << (sell? ? candle.bid : candle.ask)
    end
    
    chart = @period[26..-1]
    pos   = -
    
    mins = 0
    ema = chart.find_all do |f| f end.map do |q|
      mins +=1
      ema12 = @period[(14+pos)..(pos+26)]
      ema20 = @period[ (0+pos)..(pos+26)]
    
      pos += 1
    
      pos+1 > @period.length-1 ? (next) : (true)
    
      {
        ema12:             e12=ema12.map do |z| z end.ema,
        ema20:             e20=ema20.map do |z| z end.ema, 
        price:             q,
        signal_ema12price: signal(q, e12), 
        signal_ema26price: signal(q, e20),
        signal_ema:        signal(e12, e20)
      }
    end
  end
end


module Enumerable
  def every(n)
    (n - 1).step(self.size - 1, n).map { |i| self[i] }
  end
end 

class App
  attr_reader :base,:coin,:chart, :price, :current, :amt, :currency
  def initialize base,coin, currency
    @base = base.to_s.upcase
    @coin = coin.to_s.upcase
    @currency = currency
  
    @chart = ChartBuffer.new @base, @coin
  
    @data = {
      price: [],
      ema12: [],
      ema20: [],
      usd:   []
    }
    
    @reports = []
    @sells   = 0
    @buys    = 0
  end

  def sell amt, c
    @sells += 1
    @hold = false
    chart.sell=false
    p [:sell, amt, c]
    @currency = (amt*c)*0.9975
  end

  def buy currency, c
    @buys += 1
    @hold = true
    chart.sell=true
    p [:buy, currency, c]
    @amt = 0.9975*(currency / c.to_f)
  end

  def step
    return unless @current
        
    signal  = @current[:signal_ema12price]
    signal1 = @current[:signal_ema26price]
    
    @d = true  if signal < 1 and @d != false
    @d = false if signal == 1  and @d
    
    if @d == false and signal == -1 and @hold
      sell @amt, @price
    end  

    if @d == false and signal == 1 and !@hold
      buy @currency, @price
    end

    br = ARGV.index("-s") ? 15000 : Trex.candle("USDT-BTC").diff

    @data[:ema12] << @current[:ema12]
    @data[:ema20] << @current[:ema20]
    @data[:price] << @price
    
    r=1
    r = br if base != "USDT"
    
    if @hold
      @data[:usd] << (@price * @amt)*r
    else
      @data[:usd] << @currency   *r
    end
    
    usd =""
    usd = "(USD: #{(@price*r).trex_s(3)}) BTC- " if base != "USDT"
    
    print "\rSignal: #{signal} x #{signal1}. Price: #{usd}#{@price.trex_s}, #{@current[:ema12].trex_s}, #{@current[:ema20].trex_s}. Wallet: #{@amt.trex_s}#{coin}, #{(@currency*r).trex_s}USD, BTC == #{br.trex_s}"    
  end

  def report
    render    
    this = {pair: "#{base}-#{coin}", buys: @buys, sells: @sells, orders: @buys+@sells, coin: @amt, base: @currency}
    @reports << this
    @reports.shift if @reports.length > 60
    this
  end
  
  def log
    File.open("./ema.log", "w") do |f| f.puts @reports.to_json end
  end

  def run
    Trex.run do
      @hold      = nil
       
      if !ARGV.index("-s")
        Trex.init
        Trex.ticker "#{@base}-#{@coin}"
  
        Trex.socket.order_books("#{@base}-#{@coin}", 'USDT-BTC') do |*o|
     
        end     
      
        @current = chart.update.last
        
        Trex.timeout 60000 do
          @current = chart.update.last
          Thread.new do
            report
            log
          end
          true
        end
  
        Trex.idle do
          candle = Trex.candle("#{@base}-#{@coin}")
          @price = @hold ? candle.bid : candle.ask
        
          step
          
          true
        end
      else
        mins = 0
        chart.sim (6) do
          
          chart.update.each do |c|
            mins += 1
            break unless @current=c
            @price   = @current[:price]
                  
            step  
          end
        end
        puts
        p mins
        puts render
        exit
      end
    end
  end
  
  def render
    sort = @data[:price].sort
    step = ((sort[-1]-(sort[0]))/8)
    a = [sort[0]]
    while (a.last + step) < sort[-1]
      a << a.last+step
    end
    a << a.last+step
    
    amt = @data[:usd].map do |q| q.trex_s(3) end
    l = amt[-1]
    amt = amt.every((amt.length/a.length.to_f).floor)
    
    while amt.length > a.length
      amt.pop
    end
    
    while amt.length < a.length
      amt << l
    end
    
    amt << l    
    
    amt = amt.join("|")    
    
    Gchart.line(  
      :theme => :keynote,
      :size => '600x500', 
      :title    => "#{base}-#{coin}",
      :bg => 'efefef',
      :legend => ['Price', 'EMA12', 'EMA20', 'USD'],
      :data => [@data[:price], @data[:ema12], @data[:ema20]],
      :axis_range => [
        z=[sort[0]-step, sort[-1]+step, (step)],
        z,
        z,
      ],
      :axis_with_labels => 'x,y',
      :axis_labels => [amt, a.map do |q| q.trex_s end.join("|")],
      :max_value => sort[-1]+step,
      :min_value => sort[0]-step
    )
  end
end

require 'googlecharts'

app = App.new ARGV[0], ARGV[1], ARGV[2].to_f
app.run
