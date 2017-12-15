require 'json'

class << self
  def intratrage opt_str
    j = JSON.parse(`./bin/intra #{ARGV[0]} #{opt_str}`)
    raise j['err'] if j['err']
    @gain += j['result']['gain']
    @swaps += 1
  end

  def sell
    intratrage "-s #{@coin}"
  end

  def buy
    intratrage "#{@coin}"
  end


  def report swaps, gain
    print "\r# #{@swaps}, Gain: #{@gain.trex_s(3)}"
  end

  def run
    @coin = ARGV[-1]

    @gain  = 0
    @swaps = 0

    loop do
      sell
      
      report
      
      sleep 1
    end
  end
end

run
