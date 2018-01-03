require 'json'
require 'open-uri'
require 'coinbase/wallet'

module CB
  @env = {}
  def self.env
    @env
  end
  
  def self.env!
    ARGV.find do |a| break if a=~/\-\-account\-file\=(.*)/ end
    if account_file = $1
      env[:account_file] = account_file
      
      obj    = JSON.parse(open(account_file).read)
      key    = obj['gdax']['key']
      secret = obj['gdax']['secret']

      env[:account] = CB::Account.new(key,secret)
    end  
  end
  
  
  class Account
    attr_accessor :key, :secret, :api
    def initialize key, secret
      @key    = key
      @secret = secret
      
      @api =  Coinbase::Wallet::Client.new(api_key: key, api_secret: secret)
    
      @product_map = {}
    
      init
    end
    
    def accounts 
      api.accounts
    end
    
    def init
      accounts.each do |b|
        @product_map[b['currency']] = b['id']
      end
    end
    
    def balance sym
      raise "No Symbol: #{sym}" unless id = @product_map[sym.to_s.upcase]
    
      Balance.new api.account(id)
    end
    
    def balances
      accounts.map do |a|
        Balance.from_obj a
      end
    end
    
    def withdraw amount, dest, type: :coinbase
    
    end
    
    def deposit amount, source, type: :coinbase
    
    end    
    
    Balance = Struct.new(*(["id", "currency", "balance", "available", "hold", "profile_id"].map do |k| k.to_sym end)) do
      def self.from_obj acct
        ins = new
        
        acct.keys.each do |k|
          ins[k.to_sym] = acct[k]
        end
        
        ins
      end
      
      def avail
        available
      end
      
      def amount
        balance
      end
    end
  end  
  
  env!
  
  p env
end
