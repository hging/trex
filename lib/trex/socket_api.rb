require 'cgi'
require 'open-uri'
require 'json'

require 'grio/websocket'

module Trex
  module SocketAPI
    protected
    def self.extended ins
      ins.on :message do |e| 
        j = (JSON.parse(e.data)["M"] ||= []).find_all do |h| h["H"] == "CoreHub" end

        j.each do |o|
          if m = o["M"]
            o["A"].each do |exchg|            
              ins.instance_exec do
                update_state exchg
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
      out="./get_cookies.js"
      
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
      ua, cookie = get_cookie
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

    protected  
    def update_state exchg
      if cb=@on_update_exchange_state_cb
        cb.call exchg
      end
                
      cb = (@update_state||={})[exchg["MarketName"]]
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
    # listen to summary changes on +markets (Array<String>)_
    def summaries *markets, &b
      @update_summary ||= {}
      
      markets.each do |m|
        @update_summary[m] = b
      end  
    end
    
    # listen to deltas on +markets (Array<String>)+
    def order_books *markets, &b
      @update_state ||= {}
      
      markets.each do |m|
        @update_state[m] = b
      end
      
      puts "{H: 'corehub', M: 'SubscribeToExchangeDeltas', A: #{markets.to_json}, I: 0}"  
    end
    
    def on type, &b
      # called for every exchange
      case type
      when :update_summary_state
        @on_update_summary_state = b
      when :update_exchange_state
        @on_update_exchange_state = b
      else
        super
      end
    end
  end
end

if __FILE__ == $0
  GLibRIO.run do
    Trex::SocketAPI.connect do |s|
      markets = ["ETH-CVC"]
      
      s.on :open do
        s.order_books *markets do |state|
          p state
        end
        
        s.summaries *markets do |summary|
          p summary
        end
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
