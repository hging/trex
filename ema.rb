load "./bin/repl"

def signal a,b
  return 0 if (a <=> b) == 0
  return -1 if a < b*0.995
  return  1 if a > b*1.005
end

def order
  $c+=1
end

def buy r
  order
  $amt = ($base / r)*0.9975
  $hold = true
end

def buy r
  order
  $base = ($amt * r)*0.9975
  $hold = false
end

$base = 1000
$amt  = 0
$c    = 0

Client.repl self

connect

c.updates do |obj|
  p obj['err']
  next if obj['err']
  tick = obj['result']
  p tick['market']
  next unless tick and tick['market'].upcase == "BTC-AEON"

  puts `clear`
  
  ema   = tick['ema12']
  price = tick['last']
  
  s = signal(price, ema)
  
  $s ||= s
  $sc = (s != $s)
  
  $init = true if $sc or $init
  
  if init
    if s == -1 and $hold
      buy tick['market_order']['bid']['rate']
    elsif s == 1 and $hold
      sell tick['market_order']['ask']['rate']
    end
  end
  
  puts JSON.pretty_generate(tick)
  puts tick['market'].upcase+" Last: #{tick['last']}"
  puts "##{$c} #{$amt}COIN #{$base}BASE"
end

while true
  Thread.pass
end
