load "./bin/repl"

  def sim hours, &b
    @all = Trex.get_ticks(market)[-((60*(hours))+26)..-1].map do |q| q.close end
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
      return unless rt = (book.last || Trex.ticker(market).last)
      @period.shift 
      @period << rt
    end
    
    chart = @period[26..-1]
    pos   = 0
    
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

class << self
  def signal a,b
    return 0 if (a <=> b) == 0
    return -1 if a < b*0.995
    return  1 if a > b*1.005
  end

  def order
    @c+=1
  end

  def buy r
    order
    @amt = (@base / r)*0.9975
    @hold = true
  end

  def buy r
    order
    @base = (@amt * r)*0.9975
    @hold = false
  end

  attr_reader :ema, :tick, :price
  def rate
    if @sim
      return price
    end
  
    if @hold 
      tick['market_order']['bid']['rate']
    else
      tick['market_order']['ask']['rate']
    end
  end
  
  def step
    @offset ||= -1
    @offset += 1
    @ema   = @history['ema'][@offset] 
    @price = @history['rates'][@offset]
  end

  def run
    @base = 1000
    @amt  = 0
    @c    = 0

    Client.repl self

    connect

    c.updates do |obj|
      @tick = nil
      next if obj['err']
      @tick = obj['result']
      next unless tick and tick['market'].upcase == "USDT-BTC"

      puts `clear`
      
      @ema    = tick['ema12']
      @price  = tick['last']
      
      next unless ema and price
      
      analyze
    end

    while true
      if @sim = ARGV.index("-s")
        c.history ARGV[0], 90 do |o|
          if @history = o['result']
            while step
              analyze
            end
          end
          break
        end
      end
      Thread.pass
    end
  end
  
  def analyze
    s = signal(rate, ema)
    
    @s ||= s
    @sc = (s != @s)
    
    @init = true if @sc or @init
    
    if @init
      if s == -1 and @hold
        buy  rate
      elsif s == 1 and @hold
        sell rate
      end
    end
    
    print "\rLast: #{rate} ##{@c} #{@amt}COIN #{@base}BASE"  
  end
end

run
