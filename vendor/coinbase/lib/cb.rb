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
      key    = obj['coinbase']['key']
      secret = obj['coinbase']['secret']

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
    
      Balance.from_obj api.account(id)
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
    
    Balance = Struct.new(*(["id", "name", "primary", "type", "currency", "balance", "created_at", "updated_at", "resource", "resource_path", "native_balance"].map do |k| k.to_sym end)) do
      def self.from_obj acct
        ins = new
        
        acct.keys.each do |k|
          ins[k.to_sym] = acct[k]
        end
        
        ins
      end
      
      def avail
        balance['amount']
      end
      
      def amount
        balance['amount']
      end
      
      def native
        native_balance['amount']
      end
    end
  end 
  
  class Client
    attr_reader :account
    def initialize
      @account = CB::env[:account]
    end
    
    def sum_buys prior: nil, after: nil, day_of: nil
      s=0
      
      [:LTC,:ETH,:BTC, :BCH].each do |coin|
        all=account.api.transactions(coin.to_s, fetch_all: true)
        
        if prior
          all = all.find_all do |t| t.created_at < prior end
        end
        
        if after
          all = all.find_all do |t| t.created_at > after end
        end
        
        if day_of
        
        end 
        
        all.find_all do |t| t.type == "buy" end.map do |t| 
          s+=t.native_amount.amount.to_f
        end
      end
    
      s
    end
    
    def sum_sells prior: nil, after: nil, day_of: nil
      s=0
      
      [:LTC,:ETH,:BTC, :BCH].each do |coin|
        all=account.api.transactions(coin.to_s, fetch_all: true)
        
        if prior
          all = all.find_all do |t| t.created_at < prior end
        end
        
        if after
          all = all.find_all do |t| t.created_at > after end
        end
        
        if day_of
        
        end        
        
        all.find_all do |t|  t.type == "sell" or ((t.type == "send") and t.native_amount['amount'].to_f < 0 and (!t['to'] or !t['to']['address'])) end.map do |t| 
          amt = t.native_amount['amount'].to_f
          s += amt
        end
      end
      
      s
    end
    
    def net prior: nil, after: nil
      sum_sells(prior: prior, after: after).abs - sum_buys(prior: prior, after: after)
    end
  end 
  
  env!
  
  p env
end
