require 'readline'

$: << File.expand_path(File.join(File.dirname(__FILE__), "screen"))

class Screen
  attr_accessor :lines, :columns, :prompt, :on_input_cb
  def initialize prompt: "", columns: 100
    @lines   = 0
    @columns = columns
    @prompt  = prompt
  end
  
  def on_feed &b
    @on_feed_cb = b
  end
  
  def on_blank_feed &b
    @on_blank_feed_cb = b
  end
  
  def on_nil_feed &b
    @on_nil_feed_cb = b
  end
  
  def add_line line
    _puts line
    self.lines += 1
  end
  
  alias :_print :print
  alias :_puts :puts
  
  def clear
    clear_line -2 if prompt
      
    lines.times do
      clear_line
    end
    @lines = 0
  end

  def update &b
    clear
    b.call self
    
    return unless @poll_feed
    
    append "#{@prompt} "+(buff=Readline.line_buffer.to_s)
    point = Readline.point
    (buff.length-point).times do
      print "\b"
    end
  end
  
  def append s
    _print s
  end
  
  def clear_line idx=0
    idx = lines-1 if idx == -1
    
    _print "\033[#{idx+1}A" if idx >= 0
    _print "\r"
    _print " "*columns
    _print "\b"*columns
  end
  
  def replace idx, value
    save
    clear_line idx
    _print value
    restore
  end
  
  def save 
    print "\033[s"
  end
  
  def restore
    print "\033[u"
  end
  
  def []= idx, value
    return replace idx,value if idx < lines
    add_line value
  end
  
  def puts s
    add_line s
  end
  
  def print s
    append s
  end
  
  def poll_feed
    Thread.new do
      @poll_feed = true
      while true
        line = Readline.readline(@prompt, true)

        clear_line 0 if line
        
        if cb=@on_feed_cb       
          cb.call line if line
        end
        
        if !line and cb=@on_nil_feed_cb
          cb.call self
        end
        
        if line == "" and cb=@on_blank_feed_cb
          cb.call self
        end
      end 
    end  
  end
end
