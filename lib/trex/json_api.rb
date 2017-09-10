def print s
  return super((s+"  {API Requests: #{JSONApi.rate}}").ljust(8)) if ARGV.index("--api-rate")
  super
end

def puts s
  super s+"  {API Requests: #{JSONApi.rate}}" if ARGV.index("--api-rate")
  super
end

class JSONApi
  require 'json'
  require 'open-uri'

  require 'base64'
  require 'cgi'
  require 'openssl'

  @req=-1
  @s = nil
  @rpm  = nil
  def self.fetch url, header: {}
    @s = Time.now if @req < 0
    @req+=1
    puts "\nURL: #{url}" if ARGV.index("--urls")
    JSON.parse open(url, header).read
  end
  
  def self.rate
    secs = Time.now - @s
    mins = secs / 60.0
    
    @rpm = (@req/mins) / 60.0
  end
  
  def self.fetch_signed url, key, secret
      url = url + "&nonce=#{Time.now.to_f.to_s.gsub(".",'')}"
      fetch url, header: {'apisign' => sign(url, secret)}
  end
  
  def self.sign data,secret
    digest = OpenSSL::Digest.new('sha512')
    OpenSSL::HMAC.hexdigest(digest, secret, data)
  end
end

