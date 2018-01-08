class Commands
  def perform ins, socket, req
    send req['type'], ins, socket, req
  rescue => e
    {err: {msg: "#{e}", backtrace: e.backtrace}}
  end
  
  def address ins, socket, req
    c = req['params']['coin']
  
    {
      status: 'address',
      result: Trex.env[:account].address(c.upcase.to_sym)
    }
    
  rescue => e
    {
      status: 'address',
      err:    {
        msg: "#{e}"
      }
    }
  end
  
  def tick ins, socket, req
    m = (req['params']['market'] || socket.active)    
    if m and ins.markets[m]        
      obj = ins.tick(m)
      obj[:status] = "tick"
    else
      obj = {status: 'active', err: {msg: "No active (valid) market."}}
    end
    
    obj
  end
  
  def last_tick ins, socket, req
    m = (req['params']['market'] || socket.active)    
    i = req['params']['interval'] || :oneMin
    
    obj = {
      status: 'last_tick',
      result: Trex.last_tick(m, interval: i).to_h
    }
  rescue => e
    {
      status: 'last_tick',
      err: {
        msg:       "#{e}",
        backtrace: e.backtrace
      }
    }
  end  
  
  def withdraw ins, socket, req
    addr   = req['params']['address']
    coin   = req['params']['coin']
    wallet = req['params']['wallet']
    
    amt  = req['params']['amount'] ||= Trex.env[:balances].find do |b| b.coin == coin.to_s.upcase.to_sym end.avail
    
    if !addr and ARGV.find do |a| a =~ /\-\-wallets\=(.*)/ end
      addr = JSON.parse(open($1).read)[wallet][coin]
    end

    raise "No address!" unless addr
    
    
    {
      status: 'withdraw',
      result: Trex.env[:account].withdraw(coin, amt, addr)
    }
  rescue => e
    {
      status: 'withdraw',
      err:    "#{e}"
    }
  end

  def sum ins, socket, req
    avail = []
    total = []
    
    summaries = ins.summaries
    
    Trex.env[:balances].find_all do |b|
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
        
    {
      status: 'sum',
      result: {
        total: t,
        avail: a
      }
    }
  end

  def candle ins, socket, req
    m   = (ins.markets[req['params']['market']] || ins.markets[socket.active])
    
    if m
      obj = {
        status: 'candle',
        result: m.chart.candle.to_h
      }
    else
      obj = {status: 'candle', err: {msg: "No active (valid) market."}}
    end
  end
 
  def pair_balances ins,socket,req
    if m = (ins.markets[n=req['params']['market']] || ins.markets[socket.active])
      obj = m.get_balances
    else
      raise "Bad market: #{n}"
    end
    
  rescue => e
    {
      status: "pair_balances",
      err: {
        msg:       "#{e}",
        backtrace: e.bactrace
      }
    }
  end

  def update_balances ins,socket,req
    ins.update_balances
    
    {
      status: "update_balances",
      result: true
    }
  rescue => e
    {
      status: "update_balances",
      err: {
        msg:      "#{e}",
        backtrace: e.backtrace
      }
    }
  end
  
  def balances ins,socket,req
    update = req['params']['update']
  
    if coins=req['params']['coins']
      h = {}
      
      coins.each do |c|
        if bal=Trex.env[:balances].find do |b|
          b.coin.to_s == c.upcase
        end      
          b = get_balance_rates ins, bal, update
         
          h[c.upcase] = b
        end
      end
      
      {
        status: 'balances',
        result: h
      }
    else
      {
        status: 'balances',
        result: Trex.env[:balances].find_all do |b| 
          req['params']['nonzero'] ? b.amount > 0 : true
        end.map do |b| 
          b = get_balance_rates ins,b, update
          b
        end
      }
    end
  rescue => e
    {
      status: 'balances',
      err:    "#{e}"
    }
  end

  def trades ins, socket, req
    m = req['params']['markets']
    
    a = m.map do |market|
      Trex.trades(market)
    end
    
    {
      status: 'trades',
      result: a
    }
  end

  def get_balance_rates ins, bal, update=false
    markets = ins.summaries.find_all do |s|
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
        usd = ins.summary("USDT-#{base}")['Last']
      end
            
      b['markets'][m=s['MarketName']] = {
        rate:       r=(update ? ins.tick(m)[:result][:last] : s['Last']),
        'rate-usd': ur=usd*r,
        usd:        a=ur*bal['amount'],
      }
      
      (low = m) and (l=a) if a <= l      
      (high = m) and (h=a) if a >= h
    end
          
    b['usd']         = b['markets'][high]
    b['high-market'] = high  
    b['low-market']  = low
    
    b
  end

  def active ins, socket, req
    if m = req['params']['market']
      socket.active = m
      
      if ins.markets[socket.active]
        obj = {status: 'active', result: true}
      else
        obj = {status: 'active', err: {msg: "Bad market name."}}
      end
    else
      obj = {status: "active?", result: socket.active}
    end
  end

  def cancel ins, socket, req
    uuid = req['params']['uuid']
  
    Trex.env[:account].cancel uuid
  
    {
      status: 'cancel',
      result: {
        uuid: uuid
      }
    }
  end
    
  def order ins, socket, req
    params = req['params']
    m      = params['market'] || socket.active
    type   = params['type']
    
    p [:order, m, type]
      
    if !ins.markets[m] or !type
      obj = {
        status: 'order',
        err:    "bad values for order.",
        info:   {
          market: m,
          type:   type,
        }
      }
    else
      rate, amt = params['limit'], params['amount']
      obj = ins.markets[m].order type, limit: rate, amount: amt
    end
  rescue => e
    {
      status: 'order',
      err: {
        msg:       "#{e}",
        backtrace: e.backtrace
      }
    }
  end
  
  def history ins, socket, req
    o = req['params']
    
    market   = o['market']
    
    unless periods = o['periods']
      return({
        status: "history",
        err: {
          msg: "must specifiy periods",
        },
        info: {
          market: market,
          periods: periods
        }
      })
    end
    
    if m=ins.markets[market]
      {
        status: 'history',
        result: {
          rates: m.chart.candle_data(periods).map do |t| t.to_h end,
        }
      }
    else
      {
        status: "history",
        err: {
          msg: "No market for: #{market}.",
        },
        info: {
          market: market
        }
      }
    end
  end

  def get_ema ins, socket, req
    raise "must specifiy periods" unless periods = req['params']['periods']
    raise "must specifiy market"  unless m       = req['params']['market']
    
    offset = req['params']['offset'] ||= 0
    
    raise "No Market: #{m}" unless market = ins.markets[m]

    {
      status: 'get_ema',
      result: market.chart.ema(periods, offset)
    }
  rescue => e
    {
      status: 'get_ema',
      err: {
        msg:       "#{e}",
        backtrace: e.backtrace
      }
    }
  end
  
  def subscribe ins, socket, req
    ins.ensure_market m=req['params']['market'], socket
    
    unless socket.markets.index(m)
      socket.markets << m
    end
    
    {
      status: 'async',
      result: 'subscribe'
    }
    
  rescue => e
    obj = {
      status: 'subscribe',
      err: {
        msg:       "#{e}",
        backtrace: e.backtrace
      },
      info: req['params']['market']
    }
  end  
  
  def next_candle ins, socket, req
    raise "no market param" unless m = req['params']['market']
    raise "no subsribed market: #{m}" unless ins.markets[m]
    
    ins.markets[m].chart.on_candle(socket)
    {
      status: 'async',
      result: 'next_candle',
      info:   {
        market: m
      }
    }
  rescue => e
    {
      status: 'next_candle',
      err:    "#{e}",
      info:   {
        market: m
      }
    }
  end
  
  def get_order ins, socket, req
    raise "No UUID" unless uuid=req['params']['uuid']
    
    if o=Trex.env[:account].get_order(uuid)
      {
        status: 'get_order',
        result: o.to_h
      }
    else
      {
        status: 'get_order',
        result: nil
      }
    end
  end  
  
  def summary ins, socket, req
    raise "No market" unless m=req['params']['market']
    
    {
      status: 'summary',
      result: ins.summary(m)
    }
  end
end

class Sync
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
  
  attr_reader :commands
  def initialize pry=nil
    @commands = Commands.new
    @pry      = pry
    
    @streaming = []
    
    Trex.env[:balances] = Trex.env[:account].balances
  
    @books = {}
    
    @markets = summaries.map do |s| s['MarketName'] end
  end 
  
  def sum bool=false
    Trex.env[:balances] = Trex.env[:account].balances if bool
  
    s=commands.perform(self, STDOUT, {
      'type' => 'sum',
    })
    
    result s
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
      commands.get_balance_rates self, bal
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
  
  def withdraw dest, coin, amount
    if amount < 0
      amount = account.balance(coin.to_s.upcase.to_sym).avail * amount.abs
    end
    
    result commands.perform(self, STDOUT, {
      'type'   => 'withdraw',
      'params' => {
        'wallet' => dest,
        'coin'   => coin,
        'amount'  => amount 
      }
    })
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
    def initialize
      @ticks   = []
      @pending = []
      
      Thread.new do
        Trex.run do
          Trex.timeout 1000 do
            p :T
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
      @pending << (proc do
        p :call
        Trex.socket.order_books market do |*o|
          b.call *o
        end
      end)
    end
    
    def tick
      @ticks.each do |t| t.call end
    end
    
    def on_tick &b
      @ticks << b
    end
  end
  
  def stream market, on_tick: nil, &cb
    @wsc ||= WSC.new
    
    @wsc.on_tick &on_tick if on_tick
    
    @wsc.watch market do |b, m, *o|
      p :streamed
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
end
