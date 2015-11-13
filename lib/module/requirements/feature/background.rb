
class Backgrounder
  
  @@lock = Mutex.new
  @@processes ||= {}

  def initialize(obj)
    @obj = obj
    @auto_background = {}
  end

  def __auto_background(sym)
    @auto_background[sym] = true
  end

  def method_missing(sym, *args, **kwargs)
    args += [ **kwargs ] unless kwargs.empty?
    debug "Sending #{sym} args: #{args.inspect}"
    if @auto_background.include? sym
      background(sym, *args, **kwargs)
    else
      @obj.send(sym,*args)
    end
  end

  def background(sym, *args, background_timeout: 180, **kwargs)
    pid = nil
    meta = nil
    @@lock.synchronize do
      (pid,meta) = @@processes.find { |p,m| 
        if Process.wait(p,Process::WNOHANG)
          spam "Cleaning up background process #{p}"
          m[:input].close
          m[:output].close
          @@processes.delete(p)
          next
        end
        m[:state] == :ready 
      } || create_backgrounder
      meta[:state] = :busy
    end

    debug "Backgrounding #{@obj.class}.#{sym} via pid #{pid}"

    args += kwargs unless kwargs.empty?
    Marshal.dump( { obj: @obj, sym: sym, args: args }, meta[:input] )
    
    if select = IO.select([meta[:output]], [], [], background_timeout)
      data = Marshal.load(meta[:output])
      meta[:state] = :ready
      debug "Select (parent): #{select}"
      return data
    else
      raise Exception.new("Timeout waiting for background process #{pid}")
    end 
  end

  def create_backgrounder
    (output_parent, output_child) = IO.pipe
    (input_child, input_parent) = IO.pipe

    pid = fork do
      CCCB.instance.replace_log_tag pid: $$.to_s
      CCCB.instance.logging_transition_unthreaded
      ttl = CCCB.instance.get_setting("settings", "background_process_timeout")
      output_parent.close
      input_parent.close

      spam "Started backgrounder process #{$$}"
      
      loop do
        select = IO.select([input_child],[],[input_child],ttl)
        detail "Select: #{select}"
        break if select.nil? or select[0].empty?

        data = Marshal.load(input_child)
        detail "Got: #{data.inspect}"
        begin
          debug [ *data[:args] ]
          out = data[:obj].send(data[:sym],*data[:args])
        rescue Exception => e
          critical "Exception: #{e} #{e.backtrace}"
          out = e
        end
        detail2 "Return from #{$$}: #{out}"
        Marshal.dump(out, output_child)
      end

      output_child.close
      input_child.close

      debug "Shutdown backgrounder process #{$$}"

      Kernel.exit(0)
    end

    input_child.close
    output_child.close

    @@processes[pid] = {
      state: :ready,
      input: input_parent,
      output: output_parent
    }
    return pid, @@processes[pid] 
  end

  def self.killall
    @@lock.synchronize do
      @@processes.each do |pid,meta|
        begin
          if Process.wait(pid,Process::WNOHANG)
            meta[:output].close
            meta[:input].close
            Process.kill("INT",pid)
            Process.wait(pid)
          end
        rescue Exception => e
          info "Exception: #{e}"
        end
      end
      @@processes = {}
    end
  end
end


module Module::Requirements::Feature::Background
  extend Module::Requirements
  needs :logging

  def module_load
    default_setting 300, "settings", "background_process_timeout"
    add_command :core, "background killall" do 
      Backgrounder.killall
    end

    register_api_method :core, :"background" do |**args|
      proxy = Backgrounder.new(args[:object])
      Array(args[:methods]).each do |method|
        proxy.__auto_background(method.to_sym)
      end
      proxy
    end
  end

  def module_unload
    Backgrounder.killall
  end

  def background
    Backgrounder.new(self)
  end
end
