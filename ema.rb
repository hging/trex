require 'moving_average'

require 'trex'

class ChartBuffer
  def initialize base, coin
    @base = base
    @coin = coin
  end

  def signal b,a
    res = a <=> b
    
    return  0 if res == 0
    return  1 if a > (1.005)*b
    return -1 if a < (b*0.995)
    
    return 0
  end
  
  def sim hours, &b
    @all = Trex.get_ticks("#{@base}-#{@coin}")[-((60*(hours))+20)..-1].map do |q| q.close end

    (hours/1.5).floor.times do
      @period = @all[45..(((hours)*60)+20)].find_all do |q| q end   
      b.call
      @all.shift
    end
    
   # b.call
  end

  def update
    if !@period
      @period     = Trex.get_ticks("#{@base}-#{@coin}")[-((61*1)+20)..-1].map do |q| q.close end
      @period[-1] = Trex.candle("#{@base}-#{@coin}").diff if !ARGV.index("-s")
    end
  
    if !ARGV.index("-s")
      @period.shift 
  
      @period << Trex.candle("#{@base}-#{@coin}").diff
    end
    
    chart = @period[-46..-1]
    pos   = 0
    
    mins = 0
    ema = chart.find_all do |f| f end.map do |q|
      mins +=1
      ema12 = @period[(8+pos) .. (pos+20)]
      ema20 = @period[(pos) .. (pos+20)]
    
      pos += 1
    
      pos+1 > @period.length-1 ? (next) : (true)
    
      {
        ema12:             e12=ema12.map do |z| z end.ema,
        ema20:             e20=ema20.map do |z| z end.ema, 
        price:             q,
        signal_ema12price: signal(e12, q), 
        signal_ema:        signal(e20, e12)
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
  end

  def sell amt, c
    @hold = false
    p [:sell, amt, c]
    @currency = amt*c
  end

  def buy currency, c
    @hold = true
    p [:buy, currency, c]
    @amt = (currency / c.to_f)
  end

  def step
    return unless @current
        
    signal  = @current[:signal_ema12price]
    signal1 = @current[:signal_ema]
    
    @d = true  if signal < 1 and @d != false
    @d = false if signal == 1  and @d
    
    if @d == false and signal == -1 and @hold
      sell @amt, @price
    end  

    if @d == false and signal == 1 and !@hold
      p current
      buy @currency, @price
    end

    br = ARGV.index("-s") ? 15000 : Trex.candle("USDT-BTC").diff

    @data[:ema12] << @current[:ema12]
    @data[:ema20] << @current[:ema20]
    @data[:price] << @price
    
    if @hold
      @data[:usd] << (@price * @amt)
    else
      @data[:usd] << @currency   
    end
    
    puts "\rSignal: #{signal} x #{signal1}. Price: #{@price.trex_s}, #{@current[:ema12].trex_s}, #{@current[:ema20].trex_s}. Wallet: #{@amt.trex_s}#{coin}, #{(@currency*br).trex_s}USD, BTC == #{br.trex_s}"    
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
    
          true
        end
  
        Trex.timeout 111 do
          @price = Trex.candle("#{@base}-#{@coin}").diff
        
          step
          
          true
        end
      else
        mins = 0
        chart.sim (1.5) do
          
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
    
    amt = @data[:usd].map do |q| q.trex_s(8) end
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
