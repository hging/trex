require 'socket'
require 'json'

$account = ARGV.shift

def account_arg
  "--account-file=#{$account}"
end

module Response
  def err
    self['err']
  end
  
  def value
    self['result']
  end
  
  def status
    self['status']
  end
  
  def [] k
    super(k) or super(k.to_s)
  end
end

class Client < TCPSocket
  def poll
    buff = []
    
    rd = true
    while rd
      io, _ = IO.select([self], [], [], 0)
      
      if io and io[0]
        buff << io[0].recv(1)
      else
        rd = false
      end
    end
    
    if !buff.empty?
      raw = buff.join
    
      r=JSON.parse(raw.strip)
      r.extend Response
    end
  rescue => e
    r={'err': "#{e}"}
    r.extend Response
  end
  
  def process resp
    m = queue.shift
    self.__send__ m, resp
  rescue => e
    STDOUT.puts e
    STDOUT.puts e.backtrace.join("\n")
  end
  
  def parse_numeric name, v
    err = nil
    begin
      j = JSON.parse("{\"#{name}\": #{v}}")
      if !j[name]
        err = "No #{name} specified."
      end
      if j[name] == 0 or j[name] < 0
        err = "Bad value for #{name} !(#{name} <= 0)"
      end
      if !j[name].is_a?(Numeric)
        err = "TypeError: #{name} must be numerical"
      end
      
      v = j[name]
    rescue => e
      STDOUT.puts e
      err = "json parse error for: #{name}"
    end
    
    return err, v
  end
  
  attr_reader :queue
  def run
    @queue = []
  
    @queue << :status
    puts "echo '#{{"status" => 1}.to_json}'"  
    flush
  
    Thread.start(@connected) do
      loop do
        if resp = poll
          process resp
          STDOUT.print "\n:> "
          flush
          Thread.pass
        end
      end
    end
    
    STDOUT.puts "Connecting..."
    while !connected?
      Thread.pass
    end
    
    STDOUT.puts "\nConnected."
    STDOUT.print ":> "
    
    while cmd = Readline.readline("", true)
      if cmd =~ /^bal (.*)/
        queue << :balance
        STDOUT.puts cmd = "./bin/order #{account_arg} --balance=#{$1.upcase}"
      elsif cmd =~ /^sell (.*)/
        argv = $1.split(" ")
        m = argv[0]
        r = "diff"
        a = "all"
        
        err = nil
        
        if i=argv.index("-r")
          r = argv[i+1]
          unless ["ask","bid","last", "diff"].index(r)
            err, r = parse_numeric "rate", r
          end
        end

        if i=argv.index("-a")
          a = argv[i+1]
          
          if a =~ /^\%[0-9]+$/
          else
            unless ["all", "half"].index(a)
              err, a = parse_numeric "amt", a
            end
            a = "%50" if a == "half"
          end
        end
        
        if err
          STDOUT.puts err
          next
        end
        
        cmd = "./bin/order #{account_arg} --sell --market=#{m} --amount=#{a} --rate=#{r}"
        STDOUT.puts cmd
      elsif cmd =~ /^rate (.*)/
        coin = $1.downcase.to_sym
        base = :btc
        base = :usdt if coin == :btc
        m = "#{base}-#{coin}".upcase
        queue << :rate
        cmd = "./bin/market -i --market=#{m}"
      else
        queue << :generic
      end
      
      puts cmd
      flush
    end
  end
  
  def status resp
    @connected = resp.status == 1
  end
  
  def connected?
    @connected
  end
  
  def balance resp
    if !resp.err
      STDOUT.puts ["Avail: ", resp.value['avail'], " Total: ", resp.value['total']].join
      return
    end
    
    STDOUT.puts resp.err
  end

  def rate resp
    unless resp.err
      STDOUT.puts([
      :LOW,
      resp.value['low']['market'],
      resp.value['low']['rate'],
      :USD,
      resp.value['low']['usd'],      
      :HIGH,
      resp.value['high']['market'],
      resp.value['high']['rate'],
      :USD,
      resp.value['high']['usd'],
      ].join(" "))
    end
    STDOUT.puts resp.err if resp.err
  end
  
  def generic resp
    STDOUT.puts resp.value unless resp.err
    STDOUT.puts resp.err if resp.err  
  end
end

require 'readline'

conn = Client.new("0.0.0.0", 4567)
conn.run
