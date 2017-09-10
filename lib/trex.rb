$: << File.expand_path(File.dirname(File.expand_path(__FILE__)))

require 'trex/json_api'
require 'trex/account'

begin
  require 'grio'
  require 'trex/socket_api'  
rescue LoadError
end

class Numeric
  def trex_s
    "%.10f" % self
  end
end

module Trex
  Version = "0.0.1"
  
  class Exception < ::Exception
  end
  
  class NoGRIOError < Exception
    def initialize
      super "GLibRIO not defined. (gem: grio)"
    end
  end
  
  def self.env
    @env ||= {}
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
  
  def self.libdir
    t = ["#{File.dirname(File.expand_path($0))}/../lib/#{Meta::NAME}",
         "#{Gem.dir}/gems/#{Meta::NAME}-#{Meta::VERSION}/lib/#{Meta::NAME}"]
    t.each {|i| return i if File.readable?(i) }
    raise "both paths are invalid: #{t}"
  end  
end
