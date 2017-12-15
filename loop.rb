require 'trex'

def wait_order uuid
  until order = Trex::Order.get(Trex.env[:account], uuid)
    sleep 1
  end
  
  until order.closed?
    print "\r...                 "
    sleep 0.5
    print "\rOpen Order: #{uuid}."
    sleep 0.5
  end
  
  return order 
end

def order type, rate
  puts "Order: #{type} - Rate: #{rate}"
  
  j = JSON.parse(`./bin/order --account-file=#{Trex.env[:account_file]} --market=#{ARGV[1]} --#{type} --rate=#{rate} --amount=all`)

  if e=j['err']
    raise e
  end
  
  uuid = j['result']['uuid']
  
  puts "Opened: #{uuid}"
  
  wait_order uuid
end

def buy
  order :buy, ARGV[2]
end

def sell
  order :sell, ARGV[3]
end



class << self
  def report
    
  end

  def run
    loop do
      @order = buy
      report
      sleep 1
      @order = sell
      report
      sleep 1
    end
  end
end

run
