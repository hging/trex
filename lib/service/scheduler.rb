class Scheduler
  class Task
    attr_reader :ins, :action, :rate
    def initialize ins, action, rate
      @ins    = ins
      @action = action
      @rate   = rate
      
      @fire   = Time.now+rate 
    end
    
    def tick
      if @fire <= t=Time.now
        @fire = t+rate
        Thread.new do
          if action.respond_to?(:call)
            action.call
          else
            ins.send action
          end
        end
      end
    end
  end
  
  attr_reader :tasks
  def initialize ins, opts
    @tasks = []
    
    opts.each_pair do |a,r|
      tasks << Task.new(ins, a, r)
    end
    
    Thread.new do
      loop do
        @tasks.each do |t|
          t.tick
        end
        sleep 1
      end
    end
  end
end
