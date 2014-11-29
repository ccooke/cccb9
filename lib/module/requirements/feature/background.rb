
class Backgrounder
  def initialize(obj)
    @obj = obj
  end

  def method_missing(sym, *args, **kwargs)
    args += [ **kwargs ] unless kwargs.empty?
    debug "Sending #{sym} args: #{args.inspect}"
    @obj.send(sym,*args)
  end

  def background(sym, *args, **kwargs)
    (r, w) = IO.pipe
    pid = fork do
      begin
        r.close
        CCCB.instance.set_log_tag pid: $$.to_s
        CCCB.instance.logging_transition_unthreaded
        args += [ **kwargs ] unless kwargs.empty?
        verbose "Sending #{sym} args: #{args}"
        data = @obj.send(sym,*args)
        verbose "Got #{data}"
        dump = Marshal.dump(data)
        w.write dump
      rescue Exception => e
        critical "Exception: #{e} #{e.backtrace}"
        w.write Marshal.dump(e)
      ensure
        w.close
      end
      
      Kernel.exit(0)

      loop do
        critical "Still in subprocess #{$$}"
        sleep 1
      end
    end

    w.close
    verbose "In parent, #{r}"
    data = r.read
    r.close
    verbose "Waiting for #{pid}"
    #Process.kill "TERM",  pid
    Process.wait(pid)
    verbose "Cleaned up"
    out = Marshal.load( data )

    verbose "Here: #{out}"

    raise out if out.is_a? Exception
    out
  end
end


module Module::Requirements::Feature::Background
  extend Module::Requirements
  needs :logging

  def background
    Backgrounder.new(self)
  end
end
