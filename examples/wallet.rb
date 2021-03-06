require 'trex'
require 'grio/dsl'

def get_balances account, *currencies
  balances = {}
  
  currencies.each do |coin|
    bal = account.balance coin

    balances[coin] = bal
  end
  
  
  balances
end


key      = "7b237326fd0a49808b65cd382f762d0f"
secret   = "90011d9842284df0998b6016e952da45"
account  = Trex.account key, secret

coins = :trig,:xvg,:ltc, :btc

balances = get_balances account, *coins

Trex.run do
  Trex.timeout 12000 do
    balances = get_balances account, *coins
    true
  end
  
  print "Initializing..."
  
  Trex.socket.flash_watch(*coins.map do |c| "BTC-#{c.to_s.upcase}" end, percent: 0.97)  do |market, rate|
    p [:FLASH, market, rate]
  end
    
  Trex.timeout 11 do
    tusd = 0
    tbtc = 0
    
    begin
      btc = []
      usd = balances.map do |coin,balance|
        s = "#{coin}: $#{(amt=balance.usd).trex_s(2)}"
        
        btc << "#{coin}: #{(cb=balance.btc).trex_s(8)}"
        
        tbtc += cb
        tusd += amt
       
        s
      end.join(" ")

      print "\r #{usd} : $#{tusd.trex_s(2)} #{btc.join(" ")} : #{tbtc.trex_s(8)}".ljust(70)
    rescue TypeError => e
      print "\r Getting rates...".ljust(70)
    end
    true
  end
end

