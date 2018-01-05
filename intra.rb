load "./bin/repl"

def markets
  @markets ||= ["BTC-XVG", "USDT-XVG"]
end
Client.repl self
connect

def ids
  @ids||={}
end

def order what, type, r
  c.order market: what, type: type, limit: r do |o|
    ids[type] = o.uuid
    (@orders||={})[o.uuid] = o
  end
end

def buy what, r
  order what, :buy,  r
end

def sell what, r
  order what, :sell,  r
end

def closed *ids
  !ids.map do |id| orders[id].closed end.index(false)
end

def update *ids
  ids.each do |id|
    c.get_order id do |o|
      (@orders||={})[id] = o
    end
  end
end

def spread
  c.trades(["USDT-BTC"].push(*markets)) do |o|
    btc,a,b = o
  
    p s = (b=b[0]['Price']) / ((a=a[0]['Price'])*(br=btc[0]['Price'])) 
    
    if s > 1.0085
    
      @hold = true
      
      buy  markets[0], a

      sell markets[1], b
      
      until bid=@ids[:sell] and aid=@ids[:buy]
        Thread.pass
      end
      
      until closed(aid, bid); 
        sleep 0.5
        Thread.pass
          
        update aid,bid  
          
        break if closed(aid, bid)
        sleep 1
      end
      
      @ids[:sell] = nil
      @ids[:bid]  = nil
    
      buy "USDT-BTC",  br
    
      until bid=@ids[:bid];
        Thread.pass
      end
    
      until closed(bid);
        Thread.pass
        update bid
        sleep 1;
      end
      
      @hold = false
    end  
  end
end

loop do
  spread if !@hold
  
  sleep 5
end
