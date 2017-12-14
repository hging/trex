class Wallet
  def order_summary o, idx = nil
    a=[]
    
    a.push("Index: #{idx}") if idx
    
    a.push(*[
      "Market: #{o.market}", "Rate: #{o.limit}",
      "Amount: #{o.quantity}",
      "Type: #{o.type}"
    ])
    
    a.push("Price/Unit: #{o.price_per_unit}", "Price: #{o.price}") if !@update
    
    a.join(", ")  
  end

  def order_aide(market, coin, *args)
    u = nil
    if args[1] == "usd"
	  args.delete_at(1)
  	  u = Float(args.delete_at(1))
    end

    args[1] = Trex.candle(market).bid  if args[1] == "bid"
    args[1] = Trex.candle(market).ask  if args[1] == "ask"
    args[1] = Trex.candle(market).diff if args[1] == "diff"            

    rate    = args[1] || Trex.candle(market).diff
    amount  = u ? (u / Trex.usd(coin,1)) : (args[2] || -1)  
  
    return rate,amount
  end
    
  def convert from, to
    middle = :BTC
  
    execute "sell", from
    if lo
      uuid = lo.uuid
      
      pre_bal = account.balance(middle)
      pre_bal = pre_bal.amount
      
      on_order_filled do |o|
        if uuid == o.uuid
          expected = (o.quantity * o.rate)
        
          if account.balance(middle).amount >= pre_bal+(expected*0.9975)
            execute "buy", to, "diff", (expected*0.9975).to_s
            if lo
              uuid = lo.uuid
              on_order_filled do |o|
                if o.uuid == uuid
                  message "Convert #{from} to #{to}, Complete"
                end
              end
            else
              message "Convert #{from} to #{to}, failed: buy <to>"
            end
          else
            message "Convert #{from} to #{to}, failed: amounts mismatch"
          end
        end
      end
    else
      message "Convert #{from} to #{to}, failed: sell <from>"
    end
  end

  def history *args
    orders = account.history market: args[0]
    message(orders.map do |o|
      order_summary o
    end.join("\n"))
  end
  
  def view what, *args
    @update = false
    screen.clear
    execute what, *args[0..-1]
    @msg_buff.split("\n").each do |l| screen.puts l end  
  end

  def stash args
    target = args[0] || :USDT
              
    get_balances(account,[]).each do |bal|
      next if bal.coin == :BTC
      next if bal.coin == target
      
      market = "BTC-#{bal.coin}"
      `#{order_exe} --account-file=#{Trex.env[:account_file]} --market=#{market} --rate=diff --amount=-1 --sell`
    end

    Trex.idle do
      list = balances.map do |bal| bal.coin end.sort
      if list == [:BTC, target].sort or list == [:BTC]
        `#{order_exe} --account-file=#{Trex.env[:account_file]} --market=USDT-BTC --rate=diff --amount=-1 --sell`
        next false
      else
        next true
      end
    end
  end

  def withdraw *args
    group = wallets[args[0]]
    coin  = args[1].to_s.upcase.to_s.to_sym
    if args[1] and addr = group[coin.to_s]
      if !args[2]
        begin
          message(account.withdraw!(coin, addr)["uuid"])
        rescue => e
          message(e.to_s)
        end
      elsif amt=args[2]
        begin
          amt = Float(amt)
          message(account.withdraw(coin, amt , addr)["uuid"]) 
        rescue => e
          message(e.to_s)
        end
      end
    elsif coin
      begin
        amt = Float(args[2])
        account.withdraw(coin, amt , args[0]) 
      rescue => e
        message(e.to_s)
      end
    end
  end

  def withdrawals *args  
    message(account.withdrawals(args[0] ? args[0].upcase.to_sym : nil).map do |w|
      "#{w.currency} #{w.amount} #{w.txid} #{w.pending}"
    end.join("\n"))
  rescue => e
    message(e.to_s)
  end
  
  def execute cmd, *args
    case cmd.to_s
    when 'watch'
      if args[0] != "open"
        coin = args[0].to_s.upcase.to_sym
    
        balances << account.balance(coin) unless balances.find do |bal| bal.coin == coin end
        watching << coin                  unless watching.index(coin)
      else
        execute "open"
        oa.each do |o|
          execute "watch", o.market.split("-")[1]
        end
      end
    when "convert"
      convert *args
    when "cancel"
      u=nil
      if !args[0] and lo and lo.uuid
        `#{order_exe} --cancel='#{u=lo.uuid}' --account-file=#{Trex.env[:account_file]}`
      elsif args[0] == "all"
        `#{order_exe} --cancel=all --account-file=#{Trex.env[:account_file]}`
      elsif args[0] == "market"
        `#{order_exe} --cancel=true --market='#{args[1]}' --account-file=#{Trex.env[:account_file]}`
      elsif args[0] =~ /^([0-9]+)/ and !oa.empty?
        `#{order_exe} --cancel='#{u=oa[$1.to_i].uuid}' --account-file=#{Trex.env[:account_file]}`
      end
      # if u
      #   o=@open.find do |o| o.uuid == u end
      #   @open.delete o if o
      # end
    when 'buy' 
      market = "BTC-#{args[0].upcase}"
    
      rate, amount = order_aide(market, :BTC, *args)
      
      message "BUY Order "+lo=`#{order_exe} --account-file=#{Trex.env[:account_file]} --market=#{market} --rate=#{rate} --amount=#{amount} --buy`
      begin
        lo = JSON.parse(lo)
        @open << self.lo=Struct.new(:uuid).new(lo["uuid"])
      rescue => e;message e.to_s;
        self.lo=nil
      end
    when 'sell' 
      if args[0] == "all"
        balances.each do |b|
          if (b.avail*b.rate(type: @rate)) > 0.0005
            if b.coin != :USDT
              execute "sell", b.coin.to_s if b.coin != :BTC
            end
          end
        end
        
        return
      end

      market = "BTC-#{coin=args[0].upcase.to_sym}"
    
      rate, amount = order_aide(market, coin, *args)
      
      command = "#{order_exe} --account-file=#{Trex.env[:account_file]} --market=#{market} --rate=#{rate} --amount=#{amount} --sell"
     
      message "SELL Order "+lo=`#{command}`
     
      begin
        lo = JSON.parse(lo.strip)
        @open << self.lo=Struct.new(:uuid).new(lo["uuid"])
      rescue => e ;message e.to_s;
        self.lo=nil
      end
    when "addr"
      coin = args[0]
      message "#{coin.upcase} Deposit Address: #{account.address(coin)}"
    when "eval"
      message res="#{`ruby -e "p(#{args.join(' ')})"`}"
      screen.puts res if @eval_mode
    when "rate"
      message Trex.btc(args[0],1).trex_s
    when "usd"
      message Trex.usd(args[0],1).trex_s(3)    
    when "btc-rate"
      if args[0] == "gdax"
        update_gdax unless @enable_gdax
        message "Rate: Using GDAX for USD conversion" 
      end
      message "Rate: using bittrex market data" if !args[0]
      @btc_rate_override = args[0]
    when "api-rate"
      message Trex::JSONApi.rate.to_s
    when "uuid"
      if !args[0] and lo and uuid=lo.uuid
        message "Laster Order UUID: #{uuid}"
      elsif !oa.empty? and idx=args[0]
        o = oa[idx.to_i]
        message("UUID: #{o.uuid}")
      else
        message "UUID: No Orders this Session"
      end
    when "open"
      if args[0].to_s =~ /^([0-9]+)/
        o = oa[idx=$1.to_i]
        
        if !o
          message("No order")
          return
        end
        
        message(order_summary(o, idx))
        return
      end
    
      self.oa = account.orders.find_all do |o|
        args[0] ? o.market == args[0] : true
      end
      
      idx=-1
      a=oa.map do |o|
        order_summary(o,idx+=1)
      end
      message(a.empty? ? "No Orders" : a.join("\n"))
    when "repeat"
      repeat *args
    when "nonzero"
      balances.find_all do |bal| watching.index bal.coin end.each do |bal| balances.delete bal end
      self.watching = []
    when "withdrawals"
      withdrawals *args
    when "withdraw"
      withdraw *args
    when "history"
      history *args
    when "stash"
      stash()
    when "clear"
      screen.clear
    when "when"
      query = nil
      type  = args[0]
      qi    = 1
      
      if args[1] == "of"
        qi = 3
      end
      
      if [">=","<=",">","<","=="].index(op=args[qi])
        @when << (proc do
          if qi == 3
            bal = balance(args[2].upcase.to_sym)
            
            query = bal.usd  if type == "usd"
            query = bal.btc  if type == "btc"
            query = bal.rate(type: @rate) if type == "rate"
            query = Trex.usd(args[2].upcase.to_sym, 1)  if type == "rate-usd"
          end
          
          amt   = Float(args[qi+1])
          query = instance_variable_get("@#{type}").to_f unless query
          
          if query.send(op.to_sym, amt)
            execute *args[qi+2..-1]
          end
        end)       
      end
    when "as"
      coin = args[0].to_s.upcase.to_sym
      if coin != @as
        @as = coin
        @as_amt = nil
      end
      if args[1] == "at"
        @as_rate = Float(args[2])
      else
        @as_rate = Trex.btc(coin,1)
      end
      @as_amt ||= @btc / Trex.btc(coin,1)
      message("#{@btc.trex_s}BTC: as #{@as} at rate: #{@as_rate} "+Trex.usd(:BTC, @as_amt * @as_rate).trex_s(3))
    when "toggle"
      @update = !@update
      screen.clear
    when "view"
      if !(what=args[0])
        @update = true
        screen.clear
        @eval_mode = @pending = false
      elsif ["bid", "ask", "diff"].index(what)
        @rate = what.to_sym
      elsif what == "pending"
        @pending = true
      elsif what == "open"
        view what, *args[1..-1]
      elsif what == "withdrawals"
        view what, *args[1..-1]
      elsif what == "eval"
        @eval_mode = true
      elsif what == "addr"
        view what, *args[1..-1]
      elsif what == "halt"
        @update = false
      elsif what == "history"
        view what, *args[1..-1]
      end
    end
  rescue => e
    message e.to_s
  end
  
  def repeat coin, buyin, target, amt=nil
    coin = coin.to_s.upcase.to_sym
    
    execute "watch", coin.to_s
    execute "watch", "BTC"
    
    buyin  = buyin.to_f
    target = target.to_f
    amt    = amt.to_f    if amt
    
    amt = nil if amt == -1
    
    uuid = order = nil
    
    if order=@open.find do |o| o.market == "BTC-#{coin}" end
      uuid = order.uuid
    else
      cb = balances.find do |q| q.coin.to_sym == coin end
      b  = balances.find do |q| q.coin.to_sym == :BTC end
      
      if cb and b
        if cb.btc > b.avail
          a = amt
          a = amt / cb.rate  if a
          execute "sell", "#{coin}", target.trex_s, (a ? a.trex_s : "-1")      
        else
          execute "buy", coin, buyin.trex_s, (amt ? amt.trex_s : "-1")
        end
      elsif b and b.avail > 0.0005
        execute "buy", coin, buyin.trex_s, (amt ? amt.trex_s : "-1")
      end
      
      if lo
        uuid = lo['uuid']
      end
    end
    
    if uuid
      on_order_closed do |o|
        message o.type
        if o.uuid == uuid
          if o.type == "LIMIT_SELL"
            execute "repeat", coin, buyin.trex_s, target.trex_s, ((a=(amt || -1)) == -1 ? "-1" : a.trex_s)
            next if lo
          elsif o.type == "LIMIT_BUY"
            execute "sell", coin.to_s, target.trex_s, ((o.price / o.price_per_unit)*0.9975).to_s
            if lo
              execute "repeat", coin.to_s, buyin.trex_s, target.trex_s, ((a=(amt || -1)) == -1 ? "-1" : a.trex_s)
              next
            end
          end
        end
        
        message "Repeat: #{coin} - END"
      end
    else
      message "Repeat: #{coin} - END"
    end
  rescue => e
    raise e
  end
end
