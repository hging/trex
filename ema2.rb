require 'moving_average'
load "./bin/repl"
Client.repl self

connect

$c = 0.03
$a = 60

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
  return :hold if ($c*0.5) < 0.001
  $lb = r
  $a += (($c*0.5)/r)*0.9975
  $c = $c*0.5
  [:buy, r]
end

$lb = nil
def sell r
      return :hold if ((($a*0.9)*r)*0.9975) < 0.001
      a = $a*0.1
      $c += (($a*0.9)*r)*0.9975    
      $a=a
      [:sell, r]
end

c.subscribe "BTC-AEON" do
  c.history "BTC-AEON", ARGV[0].to_i do |h|
    p h
    all = h['result']['rates'].map do |c| c['close'] end
    p all.length
    chart = all[12..-1]
  
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
    p bsh
    p [$c, $a, ($c*18500)+(($a*lr*0.9975)*18500)]
  end
end

while true
  Thread.pass
end
