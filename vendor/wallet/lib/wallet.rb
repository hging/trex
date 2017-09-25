require 'screen'
require 'screen/colourize'

$: << File.expand_path(File.join(File.dirname(__FILE__), "wallet"))

require 'wallet/wallet'
require 'wallet/commands'
require 'wallet/gdax'
