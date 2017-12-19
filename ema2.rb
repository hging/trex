require 'moving_average'
load "./bin/repl"
Client.repl self

connect

$c = 0.01
$a = 20

def order? r,e
  if r > e*1.005
    sell r
  elsif r < e*0.995
    buy r
  else
    :hold
  end
end

def buy r
  $lb = r
  $a += (($c*0.5)/r)*0.9975
  $c = $c*0.5
  :buy
end

$lb = nil
def sell r
      a = $a*0.1
      $c += (($a*0.9)*r)*0.9975    
      $a=a
      :sell
end

c.subscribe "BTC-AEON" do
  c.history "BTC-AEON", 120 do |h|
    p h
    all = h['result']['rates'].map do |c| c['close'] end
    
    chart = all[-61..-1]
   
    ema = []
    p [$c, $a, $c*18500]
    offset = 0
    lr=nil
    bsh = []
    chart.each do |r|
      $lb ||= r
      
      p rng=offset..(offset+12)
      ema << e=all[rng].ema
      offset += 1
   
      bsh << order?(r,e)
      lr=r
    end
    
    p ema
    p [$c, $a, ($c*18500)+($a*lr*0.9975)]
  end
end

while true
  Thread.pass
end
