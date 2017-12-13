require 'moving_average'

require 'trex'

class ChartBuffer
  attr_accessor :book, :amt, :currency
  def initialize base, coin
    @base = base
    @coin = coin
  end

  def signal a,b
    res = a <=> b
    
    return  0 if res == 0
    return -1 if a > b
    return  1 if a < b
    
    return 0
  end
  
  def sim hours, &b
    @all = Trex.get_ticks("#{@base}-#{@coin}")[-((60*(hours))+26)..-1].map do |q| q.close end
    @period = @all[45..(((hours)*60)+26)].find_all do |q| q end   
    b.call if b
  end

  def sell?
    @sell
  end
  
  attr_accessor :sell

  def update
    if !@period
      sim 1.5
    end
  
    if !ARGV.index("-s")
      @period.shift 
  
      if sell?
        rt = book.rate_at(amt, :bid)
        return unless rt
        return unless rt < Float::INFINITY
        @period << rt
      else
        a = book.amt_for(currency, :ask)
        return unless a
        
        rt = currency / a.to_f
        
        return unless rt < Float::INFINITY
        @period << rt
      end
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
  attr_reader :base, :market, :book, :coin,:chart, :price, :current, :amt, :currency
  def initialize base,coin
    @base = base.to_s.upcase
    @coin = coin.to_s.upcase
    
    @market = "#{@base}-#{@coin}"

    Trex.init
    Trex.ticker market
      
    @chart = ChartBuffer.new @base, @coin
  
    balances
  
    @s_usd = t_usd
  
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
  
  def balances
    @currency = Trex.env[:account].balance(base).avail.to_f
    @amt      = Trex.env[:account].balance(coin).avail.to_f
    
    chart.currency = currency
    chart.amt      = @amt
  end
  
  def act
    Trex.env[:account]
  end
  
  def order type, vol, rate
    return true if ARGV.index("-s") or ARGV.index("-S")
  
    cmd="ruby ./bin/order --account-file=#{Trex.env[:account_file]} --#{type} --market=#{base}-#{coin} --rate=#{rate} --amount=all"
    puts cmd
    res = `#{cmd}`
    
    json = JSON.parse(res)
    
    unless !json["err"]
      puts json
      exit
    end
    
    uuid = json["result"]["uuid"]
    order = nil
    puts res
    p({uuid: uuid, rate: rate, vol: vol})
    until order and order.closed?
      order=Trex.env[:account].get_order(uuid)
      sleep 1
      puts "order: #{uuid} open"
    end
    
    balances
    
    puts "order: #{uuid} closed"
    
    true
  end
  
  def sell amt, c
    if res=order(:sell, amt, c)
      @sells += 1
      @hold = false
      chart.sell=false
    
      puts
      p [:sell, amt, c]
      @currency = (amt*c)*0.9975 if ARGV.index("-s") or ARGV.index("-S")
      chart.sell=false
    end
  end

  def buy currency, c
    if order(:buy, currency,c)
      @buys += 1
      @hold = true
      chart.sell=true
      puts
      p [:buy, currency, c]
      @amt = 0.9975*(currency / c.to_f) if ARGV.index("-s") or ARGV.index("-S")
      chart.sell=true
    end
  end

  def candle
    Trex.candle("#{base}-#{coin}")
  end

  attr_accessor :signal1, :signal
  def step
    return unless @current
        
    @signal  = @current[:signal_ema12price]
    @signal1 = @current[:signal_ema26price]
    
    @d = true  if @signal < 1 and @d != false
    @d = false if @signal == 1  and @d
    
    if ARGV.index("-h")
      @d    = false
      @hold = true
    end

    if ARGV.index("-b")
      @d    = false
      signal = 1
      ARGV.delete "-b"
    end
    
    ts=ARGV.index("--ts")
    tb=ARGV.index("--tb")
    
    if (ts) or (@d == false and @signal == -1 and @hold)
      sell @amt, @price
    end  

    if (tb) or (@d == false and @signal == 1 and !@hold)
      buy @currency, @price
    end

    exit if tb or ts

    br = ARGV.index("-s") ? 16000 : Trex.candle("USDT-BTC").diff
    r  = 1
    r  = br if base != "USDT"
    
    if ARGV.index("-s")  
      @data[:ema12] << @current[:ema12]
      @data[:ema20] << @current[:ema20]
      @data[:price] << @price
    
      
      @data[:usd] << t_usd
    end
  end

  def br
    br = ARGV.index("-s") ? 16000 : Trex.candle("USDT-BTC").diff
  end
  
  def r
    r  = 1
    r  = br if base != "USDT"  
    r
  end

  def t_usd
    @price ||= Trex.candle(market).diff
    
    ARGV.index("-s") ? @currency*r : ((@currency*r)+(@amt*@price*r))
  end

  def report
    puts render if ARGV.index("-s")    
    
    this = {
      pair:   "#{base}-#{coin}",
      start:  @s_usd,
      buys:   @buys, 
      sells:  @sells, 
      orders: @buys+@sells, 
      coin:   @amt, 
      base:   @currency,
      USD:    eu=@data[:usd].last,
      pct:    eu/@s_usd
    }
    
    @reports << this
    @reports.shift if @reports.length > 60
    
    this
  end
  
  def log
    File.open("./ema.log", "w") do |f| f.puts @reports.to_json end
  end
  
  def status
    return unless @current
    usd =""
    usd = "(USD: #{(@price*r).trex_s(3)}) BTC- " if base != "USDT"
    
    print "\rSignal: #{@signal} x #{@signal1}. Price: #{usd}#{@price.trex_s}, #{@current[:ema12].trex_s}, #{@current[:ema20].trex_s}. Wallet: #{@amt.trex_s}#{coin}, #{t_usd.trex_s}USD, BTC == #{br.trex_s}"    
   
  end

  def run  
    arg = ARGV.find do |a| a=~/\-\-hours\=(.*)/ end
    hrs = $1.to_f
    ARGV.delete arg
  
    Trex.run do
      @hold      = nil
       
      if !ARGV.index("-s")  
        Trex.socket.order_books(self.market, 'USDT-BTC') do |book, market, *o|
          if !@book and market == self.market
            @book      = book
            chart.book = book
            
            chart.sim 1.5 do
              upd = chart.update
              next true unless upd
              @current = upd.last
            end
          end
          
          true
        end     
        
        Trex.timeout 60000 do
          next true unless @book
          
          upd = chart.update
          next true unless upd
          @current = upd.last
          
          Thread.new do
            report
            log
          end

          next true unless (@book and @current)

          @price = current[:price]
        
          step
          
          true
        end
      
        Trex.idle do
          status
          true
        end
      else
        mins = 0
        chart.sim (hrs) do
          
          chart.update.each do |c|
            mins += 1
            break unless @current=c
            @price   = @current[:price]
                  
            step
            status  
          end
        end
        puts
        puts JSON.pretty_generate report
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

app = App.new ARGV[0], ARGV[1]
app.run