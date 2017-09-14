$: << File.expand_path(File.dirname(File.expand_path(__FILE__)))

require 'trex/json_api'
require 'trex/account'

begin
  require 'grio'

  begin
    require 'trex/socket_api'  
  rescue LoadError
  end
rescue LoadError
end


class Numeric
  def trex_s amt=10
    "%.#{amt}f" % self
  end
end

module Trex
  VERSION = "0.0.1"
  
  class Exception < ::Exception
  end
  
  class NoGRIOError < Exception
    def initialize
      super "GLibRIO not defined. (gem: grio)"
    end
  end
  
  def self.env
    @env ||= {last_n_ticks: {}, averages: {}}
  end
  
  if Object.const_defined?(:GLibRIO)
    env[:grio] = true
  end
  
  def self.grio!
    return true if env[:grio]
    raise NoGRIOError.new
  end
  
  def self.main
    grio!
   
    GLibRIO.run
  end
  
  def self.run &b
    grio!
    GLibRIO.run &b
  end
  
  def self.quit
    grio!
    GLibRIO.quit
  end
  
  def self.timeout int, &b
    grio!
    GLibRIO.timeout int,&b
  end  

  def self.idle &b
    grio!
    GLibRIO.idle &b
  end 
  
  def self.basedir
    t = ["#{File.dirname(File.expand_path(__FILE__))}/..",
         "#{Gem.dir}/gems/trex-#{Trex::VERSION}"]
    t.each {|i| return i if File.readable?(i) }
    raise "both paths are invalid: #{t}"
  end
  
  def self.data_dir
    File.join(basedir,"data")
  end
  
  def self.btc_usd
    env[:rates]["USDT-BTC"]
  end
  
  def self.btc coin, amt
    return amt if coin.to_s.upcase == "BTC"
    amt * env[:rates]["BTC-#{coin.to_s.upcase}"]
  end
  
  def self.usd coin=nil, amt=1, market: nil
    coin = market.split("-")[1] if market
    self.btc(coin,amt) * btc_usd
  end
  
  private
  def self.init
    if !@init
      env[:rates] ||= {}
      ticker "USDT-BTC"
      sleep 0.333
      ticker "USDT-ETH"
      sleep 0.333
      ticker "USDT-LTC"
      sleep 0.333
      ticker "BTC-ETH"
      @init=true
    end
  end  
end

Trex.env[:cloud_flare] = ARGV.index("--trex-cloud-flare-bypass")

if __FILE__ == $0
  Trex.run do
    Trex.timeout 3000 do
      print "\r#{Trex.ticker('ETH-CVC').pp}"
      true
    end
  end
end
