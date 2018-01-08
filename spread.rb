require 'trex'
require 'trex/socket_api'

class << self
  attr_reader :markets, :books, :open
  def balances update=false
    if !ARGV.index("-s") and update
      h = {}
      Trex.env[:account].balances.find_all do |bal|
        [:BTC,:XVG,:USDT].index bal.coin
      end.each do |bal|
        h[bal.coin] = bal.avail
      end
      return @balances = h
    else
      @balances ||= {
        BTC:  150 / btc.diff,
        XVG:  150 / u.diff,
        USDT: 150
      }
    end
    
  rescue
    sleep 3
  end
  
  def simulate
	ob = balances[:BTC]
	ox = balances[:XVG]
	ou = balances[:USDT]
	
	h = {
	  BTC:  (ou*0.9975) / btc.diff,
	  XVG:  (ob*0.9975) / b.diff,
	  USDT: (ox*0.9975*u.diff),
	}
	
	@balances = h  
  end
  
  Thread.abort_on_exception = true
  def perform
    @acct ||= Trex.env[:account]
    
    
    orders = [
      [:buy,  markets[1], b.last],
      [:sell, markets[2], u.last],

      [:buy,  markets[0], btc.diff]
    ] if @spread > 1
    
    orders = [
      [:buy,  markets[2], u.last],
      [:sell, markets[1], b.last],

      [:sell, markets[0], btc.diff]
    ] if @spread < 1    
    
    orders.map do |o|
      t=Thread.new do
        @open << (oo=send(*o))
        
        oo[:market] = o[1]
        oo[:rate]   = o[2]
        
        oo
      end
      
      sleep 0.1
      
      t
    end.map do |t| t.join end
  end
  
  def sell market, rate
    @acct.sell market, (balances[market.split("-")[1].to_sym]), rate
  end

  def buy market, rate
    @acct.buy market, (balances[market.split("-")[0].to_sym]), rate
  end
  
  def run
    @books   = {}
    @open    = []
    @markets = ["USDT-BTC", "BTC-XVG", "USDT-XVG"]
    
    rates
  end
  
  def rates
    Trex.init
    Trex.run do
      p :MAIN
      Trex.socket.order_books(*markets) do |book, name, state|
        if markets.index(name) and !books[name]
          p [:init, name]
          book.trades.clear
          book.bids.clear
          book.asks.clear
          book.init name
          books[name] = book
          
          if books.keys.length == 3
            balances true
          end
        end
      end
      
      Trex.idle do
        next(true) unless books.keys.length == 3
      
        v = [spread, 1].sort
        t = v[1]-v[0]
        
        if @open.empty? and (t > 0.008)
          p [:spread, @spread]
          
          system "beep -e 1"
        
          if ARGV.index('-s')
            simulate
          else
            perform
          end
          
          sleep 1
        elsif !@open.empty?
        end
        
        true
      end 
      
      Trex.timeout 1000 do
        @open.each do |oo|
          open.delete oo if open.index(oo) and (o=@acct.get_order(oo['uuid'])) and o.closed?
        
          (balances(true)) if open.empty?
        end
          
        true
      end
      
      Trex.timeout 111 do
        next(true) unless books.keys.length == 3
        
        print `clear`
      
        books.map do |k,b|
          p [k,b.diff, usd_b]
        end
  
        puts JSON.pretty_generate({
          spread:   @spread,
          balances: (balances(false)),
          total:    total,
          coin:     balances[:XVG],
          orders:   open,
        })
        
        true
      end   
    end
  end
  
  def spread
    @spread = (u.last) / usd_b
  end
  
  def btc
    books["USDT-BTC"]
  end
  
  def b
    books["BTC-XVG"]
  end
  
  def u
    books["USDT-XVG"]
  end
  
  def usd_b
    btc.diff*b.last
  end  
  
  def total
    (balances[:BTC]*btc.diff) +
    (balances[:XVG]*u.diff)   +
    (balances[:USDT])
  end
end

run
