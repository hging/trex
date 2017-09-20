require 'cgi'
require 'open-uri'
require 'json'

require 'grio/websocket'

module Trex
  module SocketAPI
    OrderBook = Struct.new(:bids, :asks, :trades) do
      Entry = Struct.new(:type, :amount, :rate, :data) do
        def self.from_obj type, obj, data: nil
          new type, obj[:Quantity], obj[:Rate], data
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
        delta[:Buys].each do |e|
          e = Entry.from_obj :bid, e, data: e[:Type] == 1 
          next(self.bids[e.rate] = e) unless e.data
          self.bids.delete e.rate
        end
        
        delta[:Sells].each do |e|
          e = Entry.from_obj :ask, e, data: e[:Type] == 1
          next(self.asks[e.rate] = e) unless e.data
          self.asks.delete e.rate
        end  
        
        self.trades = delta[:Fills].map do |e|
          e = Entry.from_obj e[:OrderType].downcase.to_sym, e
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
    require 'gdbm'
    require 'zlib'
    @db = GDBM.new("log.trex")
    @cnt = -1
    protected
    @markets = {}
    @maps = {}
    @id=0
    def self.n_struct_id
      :"LoggedType#{@id+=1}"
    end
    
    KM={:MarketName => 10, :Buys=>11, :Sells=>12, 
      :Fills=>13, :Quantity=>14, :Rate=>15, 
      :OrderType=>16, :Type=>17, :BaseVolume=>18, 
      :Volume=>19, :Nounce=>20, :Created=>21, 
      :PrevDay=>22, :OpenSellOrders=>23, :OpenBuyOrders=>24,
      :TimeStamp => 25, :High => 26, :Low =>27, 
      :Open => 28, :Close=>29, :Last=>30,
      :Bid => 31, :Ask => 32}
      
    def self.extract e
      keys = e[0].to_s
      map = {}
      i = -1
  
      while i < keys.length-1
        key = keys[(i+=1)..i+1].to_i
        
        key = KM.find do |k,v| 
          v == key 
        end[0]
        
        q = e[1][map.length]
        
        if q.is_a?(Array)
          q = q.map do |qq|
            next extract(qq)
          end
        end
        
        if key == :OrderType
          q = q==100 ? "BUY" : "SELL"
        end
        
        map[key] = q
        
        i+=1
      end
      
      map
    end
    
    def self.trim e
      KM.map do |k,v|
        if e[k]
          (e.delete(k) and next) if [23,24,25,21, 20].index(v)
        
          if (v == 17 and e[k] == 1)
            e.delete :Quantity
          end
        
          if (q=e[k]).is_a? String
            e[v] = (idx=["BUY","SELL"].index(q)) ? 100+idx : q
          else
            e[v] = e[k]
          end
          
          e.delete k
        end
      end  
      
      e.keys.each do |k|
        trim(e[k]) if e[k].is_a?(Hash)
        
        e[k] = h2map(e[k]) if e[k].is_a? Hash
        
        if e[k].is_a?(Array)
          e[k].each_with_index do |q,i|
            trim(q) if q.is_a?(Hash)
            e[k][i] = h2map(e[k][i]) if q.is_a? Hash
          end
          
          e.delete(k) if e[k].empty?
        end
      end 
    end
    
    def self.h2map e
      va = []
      (ka=e.keys.sort).each do |k|
        va << e[k]
      end
      
      ka = ka.map do |k| "#{k}" end.join().to_i    
    
      return [ka,va]
    end
    
    def self.log o
      e = Marshal.load(Marshal.dump(o))
      
      e[:MarketName] = (@markets[o[:MarketName]] ||= @markets.length-1)
      
      trim(e)
      
      ka,va = h2map(e)
    
      @db[(@cnt+=1).to_s] = Zlib::Deflate.deflate(Marshal.dump([ka,va]))
    end
    
    @request_rates = {}
    def self.requested_rates
      @request_rates
    end
    
    def self.extended ins
      super
      
      ins.on :message do |e|
        puts e.data if ARGV.index("--trex-debug-socket-messages")
      
        j = (JSON.parse(e.data, :symbolize_names => true)[:M] ||= []).find_all do |h| h[:H] == "CoreHub" end

        j.each do |o|
          if m = o[:M]
            o[:A].each do |exchg|            
              log exchg if @request_rates[exchg[:MarketName]] and Trex.env[:log]
              
              ins.instance_exec do
                
                update_book_state exchg
              end
            end if m == "updateExchangeState"
            
            o[:A].each do |obj|
              obj[:Deltas].each do |exchg|
                log exchg if @request_rates[exchg[:MarketName]] and Trex.env[:log]
                
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
    
    class Simulator
      class SimulatedEvent
        attr_reader :data
        def initialize data
          @data = data
        end
      end
    
      def write *o;end
      def puts  *o;end
      def recv  *o;end
      def read  *o;end
      def send  *o;end
      
      def on type, &b
      
      end
      
      def initialize
        db      = SocketAPI.db
        markets = db["markets"]
        cnt     = 0
        nxt     = db[0]
        
        Trex.idle do
          if nxt
            @on[:message].call SimuatedEvent.new([{M:[{H: 'corehub', M: '', A: [nxt]}]}].to_json)
          end
          
          nxt = db[cnt+=1]
          
          !!nxt
        end
      end
    end
    
    public
    def self.connect &b      
      return Simulator.run(&b) if Trex.env[:simulate]
      
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
                
      cb = (@update_book_state||={})[exchg[:MarketName]]
      cb.call(exchg) if cb  
    end

    def update_summary exchg
      if cb=@on_update_summary_state_cb
        cb.call exchg
      end
        
      cb = (@update_summary||={})[exchg[:MarketName]]
      cb.call(exchg) if cb  
    end
    
    public
    # 
    def subscribe *markets      
      markets.each do |market|
        SocketAPI.requested_rates[market] = true
        puts "{H: 'corehub', M: 'SubscribeToExchangeDeltas', A: #{[market].to_json}, I: 0}"  
      end
    end
    
    # listen to summary changes on +markets (Array<String>)_
    def summaries *markets, &b
      @update_summary ||= {}
      
      markets.each do |m|
        SocketAPI.requested_rates[m] = true
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
        market = state[:MarketName]
         
        if struct
          if book = @books[market]
          else
            book = @books[market] = SocketAPI::OrderBook.init
          end
        
          book.update state
        
          Trex.env[:rates][market] = (book.low_ask + book.high_bid) / 2 if book.low_ask and book.high_bid
        
          cb.call book, market, state
        else
          cb.call state
        end
      end    
    end

    def self.add_summary_watch *markets, struct: true, &cb
      singleton.summaries *markets do |state|
        market = state[:MarketName]
        
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
          Trex.update_candle s
          
          if s 
            lta = (Trex.env[:last_n_ticks][market = s[:MarketName]] ||= [])
            lta << s[:Ask]
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
        
        s
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
    b.call Trex::Socket.singleton
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
