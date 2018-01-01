class Commands
  def perform ins, socket, req
    send req['type'], ins, socket, req
  rescue => e
    {err: {msg: "#{e}", backtrace: e.backtrace}}
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
    if coins=req['params']['coins']
      h = {}
      
      coins.each do |c|
        if bal=Trex.env[:balances].find do |b|
          b.coin.to_s == c.upcase
        end
          h[c.upcase] = bal.to_h
        end
      end
      
      {
        status: 'balances',
        result: h
      }
    else
      {
        status: 'balances',
        result: Trex.env[:balances].map do |b| b.to_h end
      }
    end
  rescue => e
    {
      status: 'balances',
      err:    "#{e}"
    }
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
