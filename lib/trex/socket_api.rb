require 'cgi'
require 'open-uri'
require 'json'

require 'grio/websocket'

module Trex
  module SocketAPI
    OrderBook = Struct.new(:bids, :asks, :trades) do
      Entry = Struct.new(:type, :amount, :rate, :data) do
        def self.from_obj type, obj, data: nil
          new type, obj["Quantity"], obj["Rate"], data
        end
        
        def match? amt, rate
          case type
          when :ask
            self.rate <= rate
          when :sell
            self.rate <= rate
          else 
            self.rate >= rate
          end and amt >= amt
        end
      end
      
      def update delta
        delta["Buys"].each do |e|
          e = Entry.from_obj :bid, e, data: e["Type"] == 1 
          next(self.bids[e.rate] = e) unless e.data
          self.bids.delete e.rate
        end
        
        delta["Sells"].each do |e|
          e = Entry.from_obj :ask, e, data: e["Type"] == 1
          next(self.asks[e.rate] = e) unless e.data
          self.asks.delete e.rate
        end  
        
        self.trades = delta["Fills"].map do |e|
          e = Entry.from_obj e["OrderType"].downcase.to_sym, e
        end              
      end
      
      def self.init *o
        ins = self.new(*o)
        ins.bids ||= {}; ins.asks ||= {}; ins.trades ||= {}
        ins
      end
      
      def low_ask
        asks.keys.sort[0]
      end
      
      def high_bid
        bids.keys.sort[-1]
      end
      
      def rate_at volume, type
        v = 0
        partials=[]
        
        (type == :ask ? (t=asks).keys.sort : (t=bids).keys.sort.reverse).each do |rate|
          ov=v
          v += tv=t[rate].amount
          if v >= volume 
            partials << [volume-ov,rate]
            break
          else
            partials << [tv, rate]
          end
        end
          
        cost=0
        partials.each do |a|
          cost += a[0]*a[1]
        end
          
        cost / volume
      end
      
      def amt_for base, type
        b = 0
        partials=[]
        
        (type == :ask ? (t=asks).keys.sort : (t=bids).keys.sort.reverse).each do |rate|
          ob=b
          b += tb=t[rate].amount*base
          if b >= base 
            partials << [base-ob, rate]
            break
          else
            partials << [tb, rate]
          end
        end
          
        amt=0
        partials.each do |a|
          amt += a[0]/a[1]
        end
          
        amt
      end      
    end
  
    protected
    def self.extended ins
      ins.on :message do |e| 
        puts e.data if ARGV.index("--trex-debug-socket-messages")
      
        j = (JSON.parse(e.data)["M"] ||= []).find_all do |h| h["H"] == "CoreHub" end

        j.each do |o|
          if m = o["M"]
            o["A"].each do |exchg|            
              ins.instance_exec do
                update_book_state exchg
              end
            end if m == "updateExchangeState"
            
            o["A"].each do |obj|
              obj["Deltas"].each do |exchg|
                ins.instance_exec do
                  update_summary exchg
                end
              end
            end if m == "updateSummaryState"
          end
        end
      end  
    end
    
    private
    def self.get_cookie
      out=File.join(Trex.data_dir,"get_cookies.js")
      
      obj = JSON.parse(`phantomjs #{out}`)
      
      cookie = obj["cookies"].map do |c| c["name"]+"="+c["value"] end.join("; ")
      ua     = obj["userAgent"]
      
      return [ua,cookie]
    end
    
    private
    def self.get_socket_uri cookie,ua
      raw = open("https://socket.bittrex.com/signalr/negotiate", {"Cookie"=>cookie, "User-Agent"=>ua}).read
      negotiate = JSON.parse(raw)
      uri = "wss://socket.bittrex.com/signalr/connect?transport=webSockets&clientProtocol=1.5&connectionToken=#{CGI.escape(negotiate["ConnectionToken"])}&connectionId=#{CGI.escape(negotiate["ConnectionId"])}&connectionData=%5B%7B%22name%22%3A%22corehub%22%7D%5D"
    end

    private
    def self.get_headers
      
      cookie = ""  
      ua     = "Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/51.0.2704.79 Chrome/51.0.2704.79 Safari/537.36"
      
      p((ua, cookie = get_cookie)) if Trex.env[:cloud_flare]
     
      headers={
        Connection:   'Upgrade',
        Cookie:       cookie,
        Host:         'socket.bittrex.com',
        Origin:       'https://bittrex.com',
        Pragma:       'no-cache',
        Upgrade:      'websocket',
        "User-Agent": ua
      }    
    end  
    
    public
    def self.connect &b      
      headers = get_headers
      
      GLibRIO.connect_web_socket("socket.bittrex.com", 80, uri: get_socket_uri(headers[:Cookie], headers[:"User-Agent"]), headers: headers) do |s|
        s.extend self
        b.call s
      end
    end

    private
    def update_book_state exchg
      if cb=@on_update_exchange_state_cb
        cb.call exchg
      end
                
      cb = (@update_book_state||={})[exchg["MarketName"]]
      cb.call(exchg) if cb  
    end

    def update_summary exchg
      if cb=@on_update_summary_state_cb
        cb.call exchg
      end
        
      cb = (@update_summary||={})[exchg["MarketName"]]
      cb.call(exchg) if cb  
    end
    
    public
    # 
    def subscribe *markets
      markets.each do |market|
        puts "{H: 'corehub', M: 'SubscribeToExchangeDeltas', A: #{[market].to_json}, I: 0}"  
      end
    end
    
    # listen to summary changes on +markets (Array<String>)_
    def summaries *markets, &b
      @update_summary ||= {}
      
      markets.each do |m|
        @update_summary[m] = b
      end  
    end
    
    # listen to deltas on +markets (Array<String>)+
    def order_books *markets, &b
      @update_book_state ||= {}
      
      markets.each do |m|
        @update_book_state[m] = b
      end
      
      subscribe *markets
    end
    
    def on type, &b
      # called for every exchange
      case type
      when :update_summary_state
        @on_update_summary_state_cb = b
      when :update_exchange_state
        @on_update_exchange_state_cb = b
      else
        super
      end
    end
  end
    
  module Socket
    @pending_book_watch    = []
    @pending_summary_watch = []
    
    def self.flash_watch *markets, percent: 0.9,&b
      order_books *markets do |book, market|        
        if ask = book.low_ask
          avg = average(market)
          
          if avg and (ask <= (avg*percent))
            b.call market,ask,book
          end
        end
      end
    end
    
    def self.order_books *markets, &b
      @books     ||= {}
      if @opened
        add_book_watch *markets,b
      else
        @pending_book_watch << [markets, b]
      end
      
      singleton
    end
    
    def self.summaries *markets, &b
      if @opened
        add_summary_watch *markets,b
      else
        @pending_summary_watch << [markets, b]
      end
      
      singleton
    end  
    
    private
    def self.connect &b
      SocketAPI.connect &b 
    end  
    
    def self.add_book_watch *markets, struct: true, &cb
      singleton.order_books *markets do |state|
        market = state["MarketName"]
        
        if struct
          if book = @books[market]
          else
            book = @books[market] = SocketAPI::OrderBook.init
          end
        
          book.update state
        
          cb.call book, market, state
        else
          cb.call state
        end
      end    
    end

    def self.add_summary_watch *markets, struct: true, &cb
      singleton.summaries *markets do |state|
        market = state["MarketName"]
        
        (Trex.env[:rates] ||= {})[market] = state["Last"]
        
        state = Summary.from_obj if struct
        
        cb.call market, state
      end
    end    
    
    public
    def self.singleton
      @singleton ||= connect do |s|
        class << s
          attr_accessor :on_close_cb
        end
        
        Trex.send :init 
        
        Trex.env[:streaming_rates] = true
        
        s.on :update_summary_state do |s|
          Trex.env[:rates][market = s["MarketName"]] = s["Last"]
          
          if s 
            lta = (Trex.env[:last_n_ticks][market = s["MarketName"]] ||= [])
            lta << s["Ask"]
          else
            next
          end
          
          t = 0
          lta[0..-2].each do |r| 
            if r
              t+= r
            end
          end
          
          if t > 0  
            n_avg = t / (lta.length-1)

            (Trex.env[:averages][market] ||=[]) << n_avg
          end          
        end
        
        Trex.timeout 120000 do
          la = Trex.env[:averages]
         
          la.map do |m,a|
            la[m] = a[-2..-1] if a.length > 2
          end

          true
        end
        
        Trex.timeout 3000 do
          lt = Trex.env[:last_n_ticks]
         
          lt.map do |m,a|
            lt[m] = a[-2..-1] if a.length > 2
          end
          
          true
        end        
        
        s.on :open do
          @pending_book_watch.map do |k,v|
            add_book_watch(*k,&v)
          end
          
          @pending_summary_watch.map do |k,v|
            add_summary_watch(*k,&v)
          end
          
          @opened = true        
        end
        
        s.on :close do |*o|
          Trex.env[:streaming_rates] = false
          on_close_cb.call *o if on_close_cb
        end
        
        def s.on type, &close_cb
          if type == :close
            return self.on_close_cb = close_cb
          end
          
          super
        end
      end  
    end
    
    def self.average market
      t = 0 
      aa=(Trex.env[:averages][market] ||= [])
      aa.each do |a| t = t+a end
          
      if t > 0
        return avg = t / aa.length 
      end
    
      nil  
    end    
  end
  
  def self.socket
    Socket
  end
  
  def self.stream &b
    b.call socket.singleton
  end
end

if __FILE__ == $0
  require 'trex'
  
  GLibRIO.run do
    bal  = 0.006
    amt  = 0.0
    rate = 0.0
    cycles = 0
    current = 0
    buy  = true
    sell = false
    Trex.socket.order_books "BTC-OK" do |book, market, json_obj|
      begin
        if buy
          q = book.amt_for(bal*0.9975,:ask)
          if q > amt
            amt = q
            sell = true
            buy  = false
          end
        elsif sell
          rate =  book.rate_at(amt, :bid)
          if (current=rate * amt * 0.9975) > bal
            bal = current
            sell=false
            buy=true
            cycles += 1
          end
        end
                  
        printf "\r[#{cycles} #{bal} #{amt} : #{buy ? :buy : "sell - #{(current / bal).round(3)}"}] #{market} $#{Trex.usd(market: market).trex_s}: #{book.bids.keys.sort[-1].trex_s} #{book.asks.keys.sort[0].trex_s} 1BTC = #{Trex.btc_usd.trex_s(3)} 1ETH = #{Trex.usd(:ETH, 1).trex_s(3)} 1LTC = #{Trex.usd(:LTC,1).trex_s(3)}"
      rescue
      end
    end 
  end
end

__END__
1+1;
var grio = grio || {};
grio.getCookies = {
	webpage:	false,
	page:		false,
	url:		false,
	userAgent:	false,
	init: function() {
		this.webpage	= require('webpage');
		this.page		= this.webpage.create();
		this.url		= 'http://bittrex.com';
		this.userAgent	= 'Mozilla/5.0 (Windows NT 6.3; rv:36.0) Gecko/20100101 Firefox/36.0';
		this.timeout	= 6000;
	},
	visit: function() {
		var self = this;
		userAgent = this.page.settings.userAgent = this.userAgent;
		this.page.open(this.url, function(status) {
			setTimeout(function() {
				console.log(JSON.stringify({userAgent: userAgent, cookies: phantom.cookies}));
				phantom.exit()
			}, self.timeout);
		});
	}
}
grio.getCookies.init();
grio.getCookies.visit();
