$: << File.expand_path(File.dirname(File.expand_path(__FILE__)))

require 'trex/json_api'
require 'trex/account'

begin
  require 'grio'

  begin
    require 'trex/socket_api'  if ARGV.index "--trex-socket"
  rescue LoadError
  end
rescue LoadError
end


class Numeric
  def trex_s amt=10
    "%.#{amt}f" % self
  end
end

class NilClass
  def trex_s amt=10
    "%.#{amt}f" % 0.0
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
  
  def self.vendor_dir
    File.join(basedir,"vendor")
  end  
  
  def self.bin_dir
    File.join(basedir,"bin")
  end    
  
  def self.btc_usd
    env[:rates]["USDT-BTC"]
  end
  
  def self.btc coin, amt=1
    return amt if coin.to_s.upcase == "BTC"

    if coin.to_s.upcase == "USDT"
      return amt / env[:rates][market="USDT-BTC"]
    end
    
    rate = env[:rates][market="BTC-#{coin.to_s.upcase}"]
    if !rate
      Trex.ticker market
      rate = env[:rates][market]
    end

    amt * rate
  end
  
  def self.usd coin=nil, amt=1, market: nil
    return amt if coin.to_s.upcase == "USDT"
    coin = market.split("-")[1] if market
    self.btc(coin,amt) * btc_usd
  end
  
  def self.update_candle s
    prev = (Trex.env[:rates] ||= {})[market = s[:MarketName]]
    return unless (rate = (s[:Last] || Trex.env[:rates][market]))
    Trex.env[:rates][market]   = rate
    (Trex.env[:bid]  ||= {})[market]  = s[:Bid] || ((Trex.env[:bid]  ||= {})[market])      
    (Trex.env[:ask]  ||= {})[market]  = s[:Ask] || (Trex.env[:ask]  ||= {})[market]   
    (Trex.env[:open] ||= {})[market]  = rate if !(Trex.env[:open] ||= {})[market]
    (Trex.env[:prev] ||= {})[market]  = prev unless prev == rate
    (Trex.env[:high] ||= {})[market]  = rate if rate > ((Trex.env[:high] ||= {})[market]||=rate).to_f
    (Trex.env[:low]  ||= {})[market]  = rate if rate < ((Trex.env[:low] ||= {})[market]||=rate).to_f    
  end
  
  def self.candle market
    hi    = Trex.env[:high][market]  || 0.0
    low   = Trex.env[:low][market]   || 0.0
    open  = Trex.env[:open][market]  || 0.0
    close = Trex.env[:rates][market] || 0.0
    prev  = Trex.env[:prev][market]  || 0.0   
    bid   = Trex.env[:bid][market]   || 0.0    
    ask   = Trex.env[:ask][market]   || 0.0
    
    Struct.new(:high,:low,:close,:open, :prev, :bid, :ask) do
      def rate
        close
      end
      
      def diff
        (bid+ask) / 2.0
      end
  
      def [] k
        if k == :diff
          return self.diff
        end
        
        super
      end
    end.new(hi,low,close,open, prev, bid, ask)
  end
  
  private
  def self.init
    if !@init
      env[:high]  ||= {}
      env[:low]   ||= {}
      env[:close] ||= {}
      env[:open]  ||= {}
      env[:prev]  ||= {}
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

Trex.env[:cloud_flare]   = ARGV.index("--trex-cloud-flare-bypass")
Trex.env[:socket_log]    = ARGV.index("--trex-socket-log")
Trex.env[:socket_replay] = ARGV.index("--trex-socket-replay")
Trex.env[:simulate]      = ARGV.index("--trex-simulate")

ARGV.find do |a| break if a=~/\-\-account\-file\=(.*)/ end
if account_file = $1
  Trex.env[:account_file] = account_file
  
  obj    = JSON.parse(open(account_file).read)
  key    = obj['trex']['key']
  secret = obj['trex']['secret']

  Trex.env[:account]       = Trex::Account.new(key,secret)
end

ARGV.find do |a| break if a=~/\-\-account\-key\=(.*)/ end
if key = $1
  ARGV.find do |a| break if a=~/\-\-account\-secret\=(.*)/ end
  if secret = $1
    Trex.env[:account]       = Trex::Account.new(key,secret) 
  end
end


if __FILE__ == $0
  Trex.run do
    Trex.timeout 3000 do
      print "\r#{Trex.ticker('ETH-CVC').pp}"
      true
    end
  end
end
