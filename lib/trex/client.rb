module Trex
class Client
  module HashObject
    def self.becomes o
      return o unless o.respond_to?(:"[]")
      
      return o if o.is_a?(String)
      
      o.extend self
      
      (o = o[:result] || o) if o.is_a?(self) and !o.is_a?(Array) and !o.is_a?(Struct)
      
      o
    end
    
    def [] k
      r = super(k)
      HashObject.becomes r if r
    end
    
    def method_missing m,*o
      return super if is_a?(String)
      
      if r=self[m.to_sym] or r=self[m.to_s] or self[cc=m.to_s.split("_").map do |q| q.capitalize end.join.to_sym] or self[cc]
      elsif is_a?(Hash)
        r=super unless keys.index(m.to_sym) or keys.index(m.to_s) or keys.index(cc) or keys.index(cc.to_sym)
      elsif is_a?(Struct)
        r=super unless members.index(m.to_sym) or members.index(cc) or members.index(cc.to_sym)
      end
      
      r
    end
  end
  
  def result o
    HashObject.becomes o
  end
  
  require 'moving_average'
  
  def initialize pry=nil
    @pry      = pry
    
    @streaming = []
    
    Trex.env[:balances] = Trex.env[:account].balances
  
    @books = {}
    
    @markets = summaries.map do |s| s['MarketName'] end
  end 
  
  
  def sum bool = false, balances: account.balances
    avail = []
    total = []
    
    @summaries = summaries
    
    balances.find_all do |b|
      b.amount > 0
    end.each do |b|
      if b.coin == :USDT
        avail << b.avail
        total << b.amount
        next
      end
      
      markets = summaries.find_all do |s|
        s["MarketName"].split("-")[1] == b.coin.to_s
      end.sort do |x,y|
        cr = 1
        if (base=x['MarketName'].split("-")[0]) != "USDT"
          cr = summaries.find do |s| s['MarketName'] == "USDT-#{base}" end['Last']
        end
        
        tx = x['Last'] * cr * b.amount

        cr = 1
        if (base=y['MarketName'].split("-")[0]) != "USDT"
          cr = summaries.find do |s| s['MarketName'] == "USDT-#{base}" end['Last']
        end
        
        ty = y['Last'] * cr * b.amount
        
        tx <=> ty
      end
      
      cr = 1
      if (base=markets[-1]['MarketName'].split("-")[0]) != "USDT"
        cr = summaries.find do |s| s['MarketName'] == "USDT-#{base}" end['Last']
      end
              
      total << markets[-1]['Last'] * cr * b.amount
      avail << markets[-1]['Last'] * cr * b.avail
    end
    
    t = 0
    a = 0
    
    total.each do |v| t+=v end
    avail.each do |v| a+=v end
    
    @summaries = nil
        
    result({
      total: t,
      avail: a
    })
  end
  
  require 'trex'
  def summaries
    @summaries || Trex.summaries
  end
  
  def open_orders
    Trex.env[:account].orders
  end
  
  def account
    Trex.env[:account]
  end
  
  def get_balance_rates bal, update=false
    summaries
    
    markets = summaries.find_all do |s|
      s['MarketName'].split("-")[1] == bal.coin.to_s
    end
    
    b = bal.to_h      
          
    b['markets'] = {}
          
    high = nil
    low  = markets[0]['MarketName']
    l    = markets[0]['Last']
    h    = 0
          
    markets.each do |s|
      base = s['MarketName'].split("-")[0]
            
      usd = 1
            
      if base != "USDT"
        usd = summary("USDT-#{base}")['Last']
      end
            
      b['markets'][m=s['MarketName']] = {
        rate:       r=(update ? tick(m)[:result][:last] : s['Last']),
        'rate-usd': ur=usd*r,
        usd:        a=ur*bal['amount'],
      }
      
      (low = m) and (l=a) if a <= l      
      (high = m) and (h=a) if a >= h
    end
          
    b['usd']         = b['markets'][high]
    b['high-market'] = high  
    b['low-market']  = low

    result b
  end  
  
  def buy market, amount, rate
    result account.buy(market, amount, rate)
  end

  def sell market, amount, rate
    result account.sell(market, amount, rate)
  end
  
  def order uuid
    account.get_order uuid
  end
  
  def orders
    account.orders
  end
  
  def cancel uuid
    result account.cancel(uuid)
  end
  
  def cancel_all
    a=orders.map do |o|
      o.cancel
      o
    end
    
    result a
  end
  
  def btc? coin, amount, rate
    result sell(m="BTC-#{coin.to_s.upcase}", *order_helper(:sell, m, amount, rate))  
  end
  
  def eth? coin, amount, rate
    result sell(m="ETH-#{coin.to_s.upcase}", *order_helper(:sell, m, amount, rate))  
  end
  
  def usd? coin, amount, rate
    result sell(m="USDT-#{coin.to_s.upcase}", *order_helper(:sell, m, amount, rate))  
  end 
  
  def order_helper type, market, amount,rate
    coin = (type == :sell ? market.split("-")[1] : market.split("-")[0]).upcase.to_sym
    
    if amount == :all
      amount = account.balance(coin).avail
    end

    if amount.is_a?(Numeric) and amount < 0
      amount = account.balance(coin).avail * amount.abs
    end
    
    if [:last, :ask, :bid, :diff].index(rate)
      rate = book(market, true).send(rate)
    end  
    
    return amount, rate
  end
  
  def btc! coin, amount, rate
    result buy(m="BTC-#{coin.to_s.upcase}", *order_helper(:buy, m, amount, rate))  
  end
  
  def eth! coin, amount, rate
    result buy(m="ETH-#{coin.to_s.upcase}", *order_helper(:buy, m, amount, rate))  
  end
  
  def usd! coin, amount, rate
    result buy(m="USDT-#{coin.to_s.upcase}", *order_helper(:buy, m, amount, rate)) 
  end    
  
  def book m, bool=false
    if b = @books[m]
      b.asks.clear
      b.bids.clear
      b.init m if bool and !@streaming.index(m)
    else  
      b = Trex::Market::OrderBook.init
      b.init m
    
      @books[m] = b
    end
    
    b
  end
  
  def btc rate = :last
    book("USDT-BTC", true).send rate
  end
  
  def btc2usd coin, rate = :last, btc_r = :last
    r = book("BTC-#{coin}".upcase, true).send rate
    r * btc(btc_r)
  end
  
  def last market, rate = :last
    r = book(market.upcase, true).send rate  
  end
  
  def rb coin, rate=:last
    book("BTC-#{coin}".upcase, true).send rate
  end
  
  def peek *c
    @summaries = summaries
    
    a = account.balances.find_all do |b| c.index(b.coin) end.map do |bal|
      get_balance_rates bal
    end
    
    @summaries = nil
    
    t=0
    
    o={
      markets: a=a.map do |b|
        u = 0
        t += (u=b['usd'][:usd]) if b and b['usd'] and b['usd'][:usd]
        
        {
          name:          b['high-market'],
          amount:        b[:amount],
          avail:         b[:avail],
          usd:           u,
          rate:          b['usd'][:rate],
          :'rate-usd' => b['usd'][:'rate-usd']
        } 
      end,
      usd:     t
    }
    
    result o
  end
  
  def summary m
    s=summaries.find do |s|
      s['MarketName'] == m.to_s
    end
    
    result s
  end
  
  def gdax_rate market
    obj = JSON.parse(open("https://api.gdax.com/products/#{market.upcase}/ticker").read)
    obj["price"].to_f  
  end
  
  def rates *coins, exchange: :trex 
    if exchange == :trex
      a=peek(*coins)[:markets].map do |m| 
        {
          coin: m[:name].split("-")[1],
          rate: m[:'rate-usd']
        } 
      end
      
      result a
    else
      a = coins.map do |c|
        {
          coin: c,
          rate: gdax_rate("#{c}-USD")
        }
      end
      
      result a 
    end
  end
  
  def markets
    @markets
  end
  
  def market? m
    @markets.index(m)
  end
  
  def pp o
    Pry.config.print.call(STDOUT, o, @pry)
  end 
  
  def long *coins, rate: :ask
    btc = account.balance(:BTC).avail
    amt = (0.9975)*(btc / coins.length)
    
    a=coins.map do |c|
      c = c.to_s.upcase.to_sym
      
      r = book("BTC-#{c}".upcase, true).send(rate)
      
      sleep 1
      
    #  o = btc! c, amt, r
      
    #  sleep 0.3

    #  until (oo=order(o['uuid'])) and oo.closed?
   #     sleep 2
   #   end
      
      sleep 1
      
      sells = [
        [r*1.1, 0.5],
        [r*1.2, 0.5],
        [r*1.3, 1]
      ]
      
      {
        coin: c,
        sells: sells.map do |o|
          sleep 1.5
      
          oo = btc? c, -1*o[1], o[0]
         
          result(oo)
        end,
        buy: {
          amount: amt,
          rate:   r,
        }
      }
    end
    
    result a
  end 
  
  def short rate: :bid
    a=account.balances.find_all do |b| b.coin != :USDT and b.coin != :BTC and b.avail > 0 end.map do |b|
      btc? b.coin, :all, rate
    end
    
    result a
  end
  
  def withdraw wallet, coin, amount
    if amount.is_a?(Numeric) and amount < 0
      amount = account.balance(coin.to_s.upcase.to_sym).avail * amount.abs
    end
    
    amt = amount ||= Trex.env[:balances].find do |b| b.coin == coin.to_s.upcase.to_sym end.avail
    
    if true and ARGV.find do |a| a =~ /\-\-wallets\=(.*)/ end
      addr = JSON.parse(open($1).read)[wallet.to_s][coin.to_s]
    end

    raise "No address!" unless addr

    result Trex.env[:account].withdraw(coin, amt, addr)
  end
  
  def holds filter: :amount
    r = result(account.balances.find_all do |b| b[filter] > 0 end)
  end
  
  def history market, interval: :oneMin, periods: 0..-1, field: nil
    o = Trex.get_ticks market, interval
    result(o[periods].map do |q| field ? q[field] : q end)
  end
  
  def ema length=26, position=-1, market: nil, interval: :oneMin, field: :close, ticks: nil
    ticks ||= history market, interval: interval, field: field
  
    ticks[(position-length)..(position-1)].ema length-1
  end
  
  def smma length=26, position=-1, market: nil, interval: :oneMin, field: :close, ticks: nil
    ticks ||= history market, interval: interval, field: field
  
    ticks[(position-length)..(position-1)].smma length-1
  end
  
  def study ticks, type: :ema, length: 26
    ((length)..(ticks.length-1)).map do |i|
      send type, length, i, ticks: ticks
    end
  end
  
  def chart ticks, studies: [{ema: 26}], out: "chart.png", title: "Trex Chart"
    require 'gruff'
    
    g = Gruff::Line.new
    
    g.title = title
    
    g.line_width = 1
    g.dot_radius = 1
    
    sa = studies.map do |s|
      study(ticks, type: s.keys[0], length: s[s.keys[0]])
    end
    
    len = sa.sort do |a,b| a.length <=> b.length end[0].length
    
    sa.each_with_index do |s,i|
      g.data studies[i].keys[0].to_s+studies[i][studies[i].keys[0]].to_s, s[(-1*len)..-1] 
    end
    
    g.data :Rate, ticks[(-1*len)..-1]

    g.write(out)  
  end 
  
  def chart_market market, periods: 60, interval: :oneMin, studies: [{ema: 12}, {ema: 26}], title: nil, out: nil, field: :close
    ticks = history market, interval: interval, field: field
    chart ticks[(-1*(periods+1))..-1], studies: studies, title: title || market+" Chart", out: out || "#{market}_#{Time.now}.png"
  end
  
  def study_market market, periods: 60, interval: :oneMin, studies: [{ema: 12}, {ema: 26}], field: :close
    ticks = history market, interval: interval, field: field
    
    res = {}
    
    studies.each do |s|
      res[(s.keys[0].to_s+s[s.keys[0]].to_s).to_sym] = study(ticks[(-1*(periods+1))..-1], type: s.keys[0], length: s[s.keys[0]])
    end
    
    result res
  end
  
  class WSC
    Thread.abort_on_exception = true
    
    require 'trex/socket_api'
    
    attr_accessor :watches, :pending, :ticks
    def initialize
      @ticks   = []
      @pending = []
      @watches = {}
      
      run
    end
    
    def run
      Thread.new do
        Trex.run do
          Trex.timeout 1000 do
            tick
            
            true
          end
          
          Trex.idle do
            if a=@pending.shift
              a.call
            end
            true
          end
        end
      end    
    end
    
    def watch market, &b
      @pending << (w=proc do
        Trex.socket.order_books market do |*o|
          b.call *o
        end
      end)
      
      @watches[market] = w
    end
    
    def tick
      @ticks.each do |t| t.call end
    end
    
    def on_tick &b
      @ticks << b
    end
    
    def restart
      Trex.socket.instance_variable_set("@singleton", nil)
      
      run
      
      markets = []
      
      watches.each_pair do |m, w|
        markets << m
      end
      
      Trex.socket.order_books *markets do |b,m,*o|
        watches[m].call(b,m,*o)
      end
    end
    
    def quit
      @pending << (proc do
        Trex.quit
      end)
    end
  end
  
  attr_accessor :wsc
  def stream market, on_tick: nil, &cb
    @wsc ||= WSC.new
    
    @wsc.on_tick &on_tick if on_tick
    
    @wsc.watch market do |b, m, *o|
      if !@streaming.index(m)
        @streaming << m
        @books[m]=b
        b.asks.clear
        b.bids.clear
        b.init m
      end
      
      cb.call b,m,o
    end
  end
  
  def asap market, base, percent: 0.006, pos: :buy, &cb
    pos = pos
    
    @@oo = nil
    
    stream market do |b,m,o|
      cb.call b,m,o
      
      next if @oo
      
      if b.diff <= base and pos == :buy
        if market=~/^USDT/
          @oo = usd! market.split("-")[1].upcase.to_sym, :all, :diff
        else
          @oo = btc! market.split("-")[1].upcase.to_sym, :all, :diff
        end
        
        p pos = :sell
      elsif b.diff >= base+(base*percent) and pos == :sell
        if market=~/^USDT/
          @oo = usd? market.split("-")[1].upcase.to_sym, :all, :diff
        else
          @oo = btc? market.split("-")[1].upcase.to_sym, :all, :diff
        end
        
        p pos = :buy 
      end
      
      if @oo
        Thread.new do
          until oo=order(@oo['uuid']) and oo.closed?
            sleep 2
          end
          
          sleep 1
          
          @oo = nil
        end
      end
    end
  end 
end
end
