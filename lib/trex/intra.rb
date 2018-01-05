load "./bin/repl"

def markets
  @markets ||= ["BTC-XVG", "USDT-XVG"]
end

connect

def order

end

def buy what

end

def sell what

end

def closed *ids

end

def spread
  c.trades("USDT-BTC", *markets) do |o|
    btc,a,b = o
  
    s = (b=b[0]['Price']) / ((a=a[0]['Price'])*(Br=btc[0]['Price'])) 
    
    if s > 1.0085
      @hold = true
      aid = buy  markets[0], a

      bid = sell markets[1], b
      
      until closed(aid, bid); 
        sleep 0.5
        Thread.pass
        break if closed(aid, bid)
        sleep 1
      end
      

      bid = buy "USDT-BTC",  br
    
      until closed(bid);
        Thread.pass
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
