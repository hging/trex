class ChartBuffer
  attr_reader :market, :interval
  def initialize market, interval=:min
    case interval
    when :hour
      @interval = 60
    when :min
      @interval = 1
    when :day
      @interval = 1*60*24
    end
    
    @data      = Trex.get_ticks(market)
    @on_candle = []
  end
  
  attr_reader :candle, :last
  def on_candle socket
    @on_candle << socket
  end
  
  def update r, close=false    
    if !@candle 
      @candle      = Trex::Market::Tick.new
      @candle.open = r
      
      while socket = @on_candle.shift        
        socket.put_result('next_candle', {
          current: candle.to_h,
          last:    last.to_h
        })
      end
    end
    
    return @candle if !r    
    
    @candle.close = r
    @candle.open  = r if !@candle.open     
    @candle.high  = r if !@candle.high or (r > @candle.high)
    @candle.low   = r if !@candle.low  or (r < @candle.low)
    
    if close
      @data.shift
      @data << @candle
      @last = @candle
      @candle = nil
      update last.close
    end
    
    @candle
  end
  
  def ma periods, type, offset=0, field: :close
    candle_data(periods, offset, field).send type
  end

  def ema periods, offset=0
    ma periods, :ema, offset  
  end

  def sma periods
    ma periods, :sma
  end

  def smma periods
    ma periods, :smma
  end
  
  def ema12
    ema 12
  end
  
  def ema26
    ema 26
  end
  
  def candle_data periods, offset=0, field=nil
    a = @data.every(interval)[(-1*(periods+offset))..(-1-offset)]
    if field
      a.map do |c|
        c[field] 
      end
    else
      a
    end
  end
  
  def highs periods
    candle_data(periods, :high)
  end 

  def lows periods
    candle_data(periods, :low)
  end 
  
  def chart
  
  end
end
