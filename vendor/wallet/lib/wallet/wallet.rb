class Wallet
  def message msg=@msg_buff, bool = false
    @msg_buff = msg
    @msg_line = 0 unless bool
    a=msg.to_s.split("\n")
    n = a.length > 0 ? @msg_line+1 : 0
    @message  = "Messages:".colourize(7,4)+" "+(a)[@msg_line].to_s+" [#{n} / #{a.length}]"
  end

  def get_balances account=self.account,watching=self.watching
    return(account.balances.find_all do |bal|
      bal.amount > 0 or watching.index(bal.coin.to_s.upcase.to_sym)
    end)
  end
  
  def usd bal = nil
    if !bal
      return @gdax[:BTC] if @gdax[:BTC] and btc_rate_override == "gdax"
      return btc_rate_override.to_f if btc_rate_override and  btc_rate_override != "gdax"
      return Trex.btc_usd  
    end
    
    if btc_rate_override == "gdax" and @gdax[bal.coin]
      return @gdax[bal.coin] * bal.btc if @gdax[bal.coin]
      return bal.usd
    end
    
    return @gdax[:BTC]*bal.btc if btc_rate_override == "gdax" and @gdax[:BTC]
    
    return (u = bal.usd) unless btc_rate_override
    
    return btc_rate_override.to_f*bal.btc
  end

  def print_balances balances=self.balances
    screen.puts ("COIN".ljust(6)+"      #{@pending ? "Pending" : "Amount"}".ljust(17)+"       Avail".ljust(16)+"        BTC".ljust(16)+"          USD".ljust(10)+"     Rate BTC          Rate USD").colourize(-1, bold: true)
    screen.puts "-"*screen.columns
    
    tu=0
    tb=0

    balances.each do |bal|
      tb += (b = bal.btc)*0.9975
      tu += u=usd(bal)*0.9975
    
      ap    = "#{bal.amount.trex_s.rjust(17)}"
      ap    = "#{bal.pending.trex_s.rjust(17)}" if @pending
      avail = " #{bal.avail.trex_s.rjust(16).colourize?(bal.amount.to_f > bal.avail.to_f,[-1,1],[-1,-1])}"
      
    
      screen.puts "#{bal.coin.to_s.ljust(5).colourize(-1, bold: true)} #{ap}#{avail} #{(b).trex_s.rjust(16)} #{(u).trex_s(3).rjust(10)}   #{(rt=bal.rate(type: @rate)).trex_s(10).colourize?(rt > Trex.candle("BTC-#{bal.coin}").prev, [0, 2], [0, 1])} #{(usd() * rt).trex_s(3).rjust(10)}" 
    end
    
    gdax = ""
    if @enable_gdax
      ltc = (tb / Trex.btc(:LTC,1)) * @gdax[:LTC].to_f
      eth = (tb / Trex.btc(:ETH,1)) * @gdax[:ETH].to_f
      btc = tb                      * @gdax[:BTC].to_f
    end
    gdax = "["+"GDAX - BTC: ".colourize(-1,bold: true)+btc.trex_s(3)+" ETH: ".colourize(-1,bold: true)+eth.trex_s(3)+" LTC: ".colourize(-1,bold: true)+ltc.trex_s(3)+"]"
    
    screen.puts "".ljust(screen.columns,"-")
    screen.puts "BTC:".colourize(-1, bold: true)+" #{tb.trex_s.rjust(16)} #{"USD:".colourize(-1, bold: true)} #{tu.trex_s(3).rjust(10)} #{@enable_gdax ? gdax : ""}"
    screen.puts @message.to_s
  
    @btc=tb
    @usd=tu
  end
  
  attr_accessor :account, :wallets, :lo, :oa, :screen, :order_exe, :balances, :watching, :btc_rate_override
  def initialize  order_exe: nil, columns: 110
    @order_exe = order_exe
    if !@order_exe
      ARGV.find do |a| a =~ /\-\-order\-exe=-path\=(.*)/ end
      unless @order_exe = $1
        unless @order_exe = ENV["TREX_ORDER_EXE"]
          @order_exe = "ruby #{File.expand_path(File.join(Trex.bin_dir, "order"))}"
        end
      end
    end
  
    @when = []
  
    @screen = Screen.new prompt: "TRXSH>: ".colourize(-1,bold: true), columns: columns
    @balances = []; @watching = []
    
    @lo=nil
    @oa=[]
      
    @rate = :diff  
      
    @msg_line = 0
    @msg_buff = ""
    message ""

    raise unless @account=Trex.env[:account]  

    @wallets = {}
    if ARGV.find do |a| a=~/\-\-wallets\=(.*)/ end
      obj = {}
    
      begin
        obj = JSON.parse(File.open(File.expand_path($1)).read)
      rescue => e
        message(e.to_s)
      end
    
      @wallets = obj
    end
    
    self.class.on_init.each do |b|
      instance_exec &b
    end
  end
  
  def init
    return if @init
    @init = true
    
    Trex.init

    screen.on_blank_feed do
      if (@msg_line += 1) >= (len=@msg_buff.split("\n").length)
        @msg_line = len-1
      end

      message @msg_buff, true
    end

    screen.on_nil_feed do
      if (@msg_line -= 1) < 0
        @msg_line = 0
      end

      message @msg_buff, true
    end

    screen.update do
      print_balances @balances=get_balances(account,watching)
    end  
  end
  
  def run
    init
    
    poll_orders
    
    @update = true
    
    screen.poll_feed
    
    Trex.run do
      Trex.stream do |s|#.summaries(*balances.map do |bal| "BTC-#{bal.coin}" end) do
        Trex.socket.flash_watch(*balances.map do |bal| "BTC-#{bal.coin}" end) do end
      
        screen.on_feed do |line|
          cmd, *args = line.split(" ")
          
          execute cmd, *args
        end

        Trex.timeout 2000 do
          @balances = get_balances account,watching
          true
        end
      
        Trex.timeout 100 do
          screen.update do
            print_balances self.balances
            #screen.clear
            @z ||= []
            #Graph.new.draw screen,@z.push(balances.find do |b| b.coin == :AEON end.rate(type: :diff) * usd())
            @when.each do |cb|
              cb.call
              @when.delete cb
            end
          end if @update
          true
        end
      end
    end    
  end
  
  def balance coin
    watching << coin unless watching.index(coin)
    balances.find do |b| b.coin == coin end || account.balance(coin)
  end  
  
  def poll_orders
    @loa     = []
    @open ||= []
    
    Trex.timeout 1233 do
      @open = account.orders 
      @loa.find_all do |o|
        !@open.find do |oo| oo.uuid == o.uuid end
      end.each do |o|
        on_order_removed o
      end
      
      @open.find_all do |o|
        !@loa.find do |oo| oo.uuid == o.uuid end
      end.each do |o|
        on_order_opened o
      end      
      
      @loa = @open
      true
    end 
    
    def on_order_removed o, &b
      if !b
        ((@order_callbacks ||= {})[:removed] ||= []).each do |cb| cb.call o end
        if go=account.get_order(o.uuid)
          ((@order_callbacks ||= {})[:closed]    ||= []).each do |cb| 
            cb.call go 
          end if go.closed? 
          
          del = []
          (a = (@order_callbacks ||= {})[:filled]    ||= []).each do |cb| 
            cb.call go
            del << cb 
          end if go.price
          del.each do |cb| a.delete cb end 
          
          ((@order_callbacks ||= {})[:canceled]  ||= []).each do |cb| 
            cb.call go 
          end if go.canceled? 
          
          if go.closed?
            message("Order: #{o.uuid} Removed.")
          end
        else
          message("Order: #{o.uuid} Removed.")
        end
      else
        ((@order_callbacks ||= {})[:removed] ||= []) << b
      end
    end
    
    def on_order_opened o, &b
      if !b
        ((@order_callbacks ||= {})[:opened] ||= []).each do |cb| cb.call o end
        message("Order: #{o.uuid} Opened.")
      else
        ((@order_callbacks ||= {})[:opened] ||= []) << b
      end
    end
    
    def on_order_closed &b
      ((@order_callbacks ||= {})[:closed]  ||= []) << b
    end
   
    def on_order_cancelled &b
      ((@order_callbacks ||= {})[:cancelled]  ||= []) << b
    end
    
    def on_order_filled &b
      ((@order_callbacks ||= {})[:filled]  ||= []) << b
    end        
  end
  
  @on_init = []
  def self.on_init &b
    @on_init << b if b
    return @on_init
  end
end

class Graph
  def draw screen,rates
    ymax = 15
    
    high,low = 0,0
    a=rates.sort
    high = a[-1]
    low  = a[0]
    
    max = high - low
    min = 0
   
    cols = 99
   
    rows = {}
    range = 0..-1
    range = -cols..-1 if rates.length > cols+1
    rates[range].each_with_index do |r,i|
      y = (r / high.to_f) * ymax   
      (rows[y.floor] ||= []) << i  
    end
    rows.keys.sort.each_with_index do |k,i|
      r = rows[k]
      a=[]
      a[cols] = nil
      r.each do |c|
        a[c] = "." if c
        a[c] = "*" if c and (c == rates.length-1 or c == cols-1) 
      end
      s=a.map do |q| q ? q : " " end.join()
      s=s.colourize(-1,4) if a.index "*"
      s = "#{(high * (k / ymax.to_f)).trex_s}".rjust(15)+s
      screen.puts s
    end
  end
end
