require 'cgi'
require 'open-uri'
require 'json'

require 'grio/websocket'

module Trex
  module SocketAPI
    public
    attr_accessor :h
    
    protected
    def self.extended ins
      super
      
      Trex.timeout 3500 do
        h = {}
      
        ins.h.keys.each do |k|
          h[k.to_s] = ins.h[k]
        end
      
        open('https://socket.bittrex.com/signalr/ping', h).read
      
        ins.puts "{}"
      
        true
      end
      
      ins.on :message do |e|
        puts e.data if ARGV.index("--trex-debug-socket-messages")
      
        j = (JSON.parse(e.data, :symbolize_names => true)[:M] ||= []).find_all do |h| h[:H] == "CoreHub" end

        j.each do |o|
          if m = o[:M]
            if m == "updateExchangeState"
              o[:A].each do |exchg|            
                ins.instance_exec do
                  update_book_state exchg
                end
              end
              
            elsif m == "updateSummaryState"
              o[:A].each do |obj|
                obj[:Deltas].each do |exchg|
                  ins.instance_exec do
                    update_summary exchg
                  end
                end
              end
            else
              STDOUT.puts JSON.pretty_generate(o)
            end
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
     
      @hh = headers = {
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
        s.h = headers.clone
        s.h.delete :Connection
        s.h.delete :Upgrade
        s.h.delete :Pragma
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
    
    def self.order_books *markets, &b
      @books     ||= {}
      if @opened
        add_book_watch *markets, struct: true, &b
      else
        @pending_book_watch << [markets, b]
      end
      
      singleton
    end
    
    def self.summaries *markets, &b
      if @opened
        add_summary_watch *markets, struct: true, &b
      else
        @pending_summary_watch << [markets, b]
      end
      
      singleton
    end  
    
    def self.books
      @books
    end
    
    private
    def self.connect &b
      SocketAPI.connect &b 
    end  
    
    def self.add_book_watch *markets, struct: true, &cb
      singleton.order_books *markets do |state|
        market = state[:MarketName]
         
        if true
          if book = @books[market]
          else
            book = @books[market] = Trex::Market::OrderBook.init
            book.init market
          end
        
          book.update state
          
          Trex.update_candle({
            Bid:        book.high_bid,
            Ask:        book.low_ask,
            MarketName: market
          })
        
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
        end        
        
        s.on :open do
          @pending_book_watch.map do |k,v|
            add_book_watch(*k,struct: true,&v)
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
  end
  
  def self.socket
    Socket
  end
  
  def self.stream &b
    b.call Trex::Socket.singleton
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
