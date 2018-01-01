class << self
  attr_reader :markets, :books, :clients
  
  def header
    puts `clear`
    puts 'BTC-AEON'
  end
  
  def view market
    @market = market
  end
  
  def tick m=@market.name, period=nil
    market = markets[m]
    
    if ARGV.index('--stream')
    else
      market.init_book
    end
    
    b      = market.book
    
    {
      status: 'tick',
      result: {
        market:       market.name,
    
        balances:     {
                        base: market.balances[:base].to_h,
                        coin: market.balances[:coin].to_h
                      },
    
        bid:          b.high_bid,
        ask:          b.low_ask,
        last:         b.last,
        diff:         b.diff,
    
        market_order: market.market_order_rates,
      }
    }
  rescue => e
    {
      err: {
        msg: "#{e}",
        backtrace: e.backtrace,
      },
      status: 'tick'
    }
  end

  def parse_data socket,data
    return if socket.closed? or !clients.index(socket)
    
    req = {}
    begin
      req = JSON.parse(data.strip)     
    rescue => e
      socket.puts JSON.dump({err: 'JSON Parse Error', info: data})
      return
    end
    
    obj = @commands.perform self, socket, req    
    
    socket.puts JSON.dump(obj)     
  rescue => e
    begin
      socket.puts JSON.dump({err: {msg: "#{e}", backtrace: e.backtrace}})
    rescue => e
      socket.close
      clients.delete socket
    end
  end
  
  def ensure_market name, socket=nil
    puts "populating..."
    
    begin
      markets[name] ||= Market.new(name)
    
      if socket
        socket.puts(JSON.dump(obj = {
          status: 'subscribe',
          result: {
            market: name
          }
        }))
      end
    rescue => e
      if socket
        socket.puts(JSON.dump(obj = {
          status: 'subscribe',
          err: {
            msg:       "#{e}",
            backtrace: e.bactrace
          },
          info: {
            market: name
          }
        }))
      end
    end
    
    Trex.socket.order_books(name) do |book, name, state|
      if markets[name] and !markets[name].book
        m=markets[name]
        m.book = book
       
        m.init_book(book)
      else
        chart = markets[name].chart
        l     = book.last
        
        if l          
          chart.update l
        end
        
        broadcast_tick name
      end
      
      true
    end if ARGV.index('--stream')   
  end
  
  def broadcast_tick name
    obj = tick(name)
    msg = obj.to_json(allow_nan: true)      

    clients.each do |c|
      begin
        c.puts msg if c.subscribed_to?(name)
      rescue
        clients.delete c
        c.close
      end
    end  
  end
  
  def serve!
    grio.socket.serve "0.0.0.0", 2222 do |socket|
      socket.extend Client
      socket.active  = @market.name if @market
      socket.markets = []
      
      clients << socket
      
      begin        
        socket.listen do |data|
          parse_data socket, data
        end
      rescue
        clients.delete socket
        socket.close
      end
    end   
  end
  
  def run
    @markets  = {}
    @commands = Commands.new
    
    serve!       
    
    Trex.env[:balances] = Trex.env[:account].balances
    
    @clients = []
    
    Trex.run do
      Trex.init
      
      if ARGV.index('--stream')
        connect_ws
      
        Trex.timeout 500 do
          if Trex.socket.singleton.closed?
            connect_ws
            sleep 1
          end
          
          true
        end
      end
      
      ensure_market "USDT-BTC"
     
      @market = markets["USDT-BTC"]
      
      puts "Trex::Mainloop."
      
      hash = {
        update_balances: 15, 
        summaries:       7,
        (proc do
          markets.each_pair do |k,v|
            next unless book = markets[k].book 
        
            if !ARGV.index('--stream')
              book.init k
              sleep 1 if markets.keys.length > 1
            end
            
            v.chart.update book.last(), true 
          end
        end) => 60
      }
      
      if !ARGV.index('--stream')
        hash[(proc do 
          markets.keys.each do |name|
            broadcast_tick name if clients.find do |c| c.subscribed_to?(name) end
          end
        end)] = 5
      end
      
      Scheduler.new self, hash
    end
  end
  
  def summaries
    @summaries = Trex.summaries struct: false
  end
  
  def summary name
    (@summaries || summaries).find do |s| s['MarketName'] == name end
  end
  
  def update_balances
    Trex.env[:balances] = Trex.env[:account].balances 
  rescue => e
    puts "#{e}"
  end
  
  def connect_ws
    puts "WebSocket.connect"
    markets.each_pair do |k,v|
      v.book = nil
    end
    
    Trex.socket.singleton.on :close do
      puts :closed
      sleep 1
      connect_ws
    end 
  end
  
rescue => IOError
  clients.find_all do |c| c.closed? end.each do |c| clients.delete c end
end
