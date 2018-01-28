module Util
  module HashObject
    def self.becomes o
      return o unless o.respond_to?(:"[]")
      
      return o if o.is_a?(String)
      
      return o if o.is_a?(Symbol)
      
      o.extend self
      
      (o = o[:result] || o) if o.is_a?(self) and !o.is_a?(Array) and !o.is_a?(Struct)
      
      o
    rescue
      o
    end
    
    def [] k
      r = super(k)
      HashObject.becomes r if r
    end
    
    def method_missing m,*o
      return super if is_a?(String)
      
      if r=self[m.to_sym] or r=self[m.to_s] or self[cc=m.to_s.split("_").map do |q| q.capitalize end.join.to_sym] or self[cc]
      elsif is_a?(Hash)
        r=super unless keys.index(m.to_sym) or keys.index(m.to_s) or keys.index(cc) or keys.index(cc.to_sym)
      elsif is_a?(Struct)
        r=super unless members.index(m.to_sym) or members.index(cc) or members.index(cc.to_sym)
      end
      
      r
    end
  end
end

module Tx
  require 'json'
  require 'open-uri'
  
  def self.eth id
    Util::HashObject.becomes JSON.parse(open("https://api.blockcypher.com/v1/eth/main/txs/#{id}").read)
  end
  
  def self.poll type, id, &b
    Thread.new do
      loop do
        b.call(send(type, id))
        sleep 5
      end
    end
  end
end

if __FILE__ == $0
  Tx.send ARGV[0].to_sym, ARGV[1]
end
