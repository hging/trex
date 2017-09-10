$: << File.expand_path(File.dirname(File.expand_path(__FILE__)))
require 'trex/json_api'
require 'trex/socket_api'
require 'trex/account'

class Numeric
  def trex_s
    "%.10f" % self
  end
end

module Trex
  Version = "0.0.1"
  
  def self.main
    GLibRIO.run
  end
  
  def self.run &b
    GLibRIO.run &b
  end
  
  def self.quit
    GLibRIO.quit
  end  
end
