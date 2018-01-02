class Market
  attr_reader :name, :balances, :account, :base, :coin
  attr_accessor :chart, :flash_level
  attr_writer   :book
  def initialize name
    @name        = name
    
    @base, @coin = name.split("-").map do |c| c.upcase.to_sym end
    
    @chart       = ChartBuffer.new(name) 
    @flash_level = 0
    
    @account = Trex.env[:account]
  end
  
  def balances
    {
      base: Trex.env[:balances].find do |b| b.coin == base end,
      coin: Trex.env[:balances].find do |b| b.coin == coin end
    }
  end
  
  def get_balances    
    {
      status: 'pair_balances',
      result: {
        market: name,
        base: balances[:base].to_h,
        coin: balances[:coin].to_h
      }
    }
  rescue => e
    {
      err: {
        msg:       "#{e}",
        backtrace: e.backtrace
      },
      status: "pair_balances"
    }
  end
  
  def book
    @book
  end
  
  def init_book book=nil
    @book = book
    
    if @book
      @book.bids.clear
      @book.asks.clear
      @book.trades.clear
    else
      @book = Trex::Market::OrderBook.init
    end
    
    @book.init name    
    
    @book
  end

  def market_order_rate amt, type
    rate = book.rate_at amt, type
  end
  
  def market_order_amount type
    if type == :bid
      amt = book.amt_for balances[:base].avail, type
    else
      amt = balances[:coin].avail
    end
  end
  
  def market_order_rates
    {
      bid: {
        amount: amt=market_order_amount(:bid),
        rate:   r=market_order_rate(amt, :bid),
        price:  amt*r,
      },
      ask: {
        amount: amt=market_order_amount(:ask),
        rate:   r=market_order_rate(amt, :ask),
        price:  amt*r,
      }
    }  
  end
  
  def get_market_order_rates
    {
      status: 'get_market_order_rates',
      result: market_order_rates
    }
  rescue => e
    {
      err: {
        msg:       "#{e}",
        backtrace: e.backtrace
      },
      status: 'get_market_order_rates'
    }
  end
  
  def order type, limit: nil, amount: nil
    uuid = nil
    
    type=type.to_sym
    
    t,a,r = type, nil, nil
    
    case type
    when :market_sell
      obj = market_order_rates[:ask]
      t = :sell
      a = obj[:amount]
      r = obj[:rate]
    when :market_buy
      obj = market_order_rates[:bid]
      t = :buy
      a = balances[:base][:avail]
      r = obj[:rate]
      p [t,a,r]    
    when :sell
      a = (amount || balances[:coin].avail)
      r = limit || book.diff
    when :buy
      a = (amount || balances[:coin].avail)
      r = limit || book.diff
    end
    
    [t, name, a, r]
    
    uuid = account.send(t, name, a, r)
    
    if uuid
      adj_balance t, a, r
    end
    
    {
      status: 'order',
      result: {
        uuid: uuid
      }
    }
  rescue => e
    {
      err: {
        msg:       "#{e}",
        backtrace: e.backtrace
      },
      status: 'order',
      info: {
        type:   type,
        limit:  limit,
        amount: amount
      }
    }
  end
  
  def adj_balance t, a, r
    if t == :buy
      balances[:base].avail  -= a
      balances[:base].amount -= a
      balances[:coin].avail  += ((a*0.9975)/r)
      balances[:coin].amount += ((a*0.9975)/r)
    elsif t == :sell
      balances[:coin].avail  -= a
      balances[:coin].amount -= a
      balances[:base].avail  += (a*r*0.9975)   
      balances[:base].amount += (a*r*0.9975)      
    end
  end
end
