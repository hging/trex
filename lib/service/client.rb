
module Client
  attr_accessor :active, :markets
  attr_reader :sells, :buys
  
  def subscribed_to? name
    @markets.index(name)
  end

  def put_result status, result
    puts JSON.dump({
      status: status,
      result: result
    })
  rescue
    begin
      close
    rescue; end
  end
  
  def on_err e
    STDOUT.puts "#{self} disconnected."
    false
  end
end
