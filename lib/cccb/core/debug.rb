module CCCB::Core::Debugging
  extend Module::Requirements

  needs :bot, :commands, :logging, :persist

  def module_load
    #@doc
    # Prints its parameters back to you
    add_command :debug, "echo" do |message,args|
      message.reply.summary = args.join(" ").split("\\n").join("\n")
    end
      
    #@doc
    # Prints its parameters back to you
    add_command :debug, "echo_md" do |message,args|
      message.return_markdown = true
      message.reply.summary = args.join(" ").split("\\n").join("\n")
    end

    #@doc
    # (superuser) Adds a debug trace to a hook in the current query or channel
    # This will cause a message to be printed by the bot every time the named hook is triggered
    # Useful examples include 'exception' and 'request'
    add_command :debug, "admin trace add" do |message, hooks|
      raise "Denied" unless message.user.superuser?
      default_setting true, "allowed_features", "debug_hook_trace"
      target = if message.to_channel? 
        message.channel
      else
        message.user
      end
      result = []
      hooks.map(&:to_sym).each do |h|
        message.reply("Adding debug hook to #{h}")
        add_hook :debug_hook_trace, h, top: true do |*args|
          target.msg "<debug: hook=#{h} args=#{args.inspect}>"
        end
        result << "Trace hooks for #{h}: #{get_hooks( :debug_hook_trace, h )}"
      end
    end

    #@doc
    # (superuser) Removes a debug trace from a hook
    add_command :debug, "admin trace remove" do |message, hooks|
      raise "Denied" unless message.user.superuser?
      hooks.map(&:to_sym).each do |h|
        trace_hooks = get_hooks( :debug_hook_trace, h )
        trace_hooks.each do |tr_h|
          message.reply("Removing debug hook from #{h}")
          remove_hook(:debug_hook_trace, h, tr_h[:source_file], tr_h[:source_line])
        end
      end
    end

    #@doc
    # (superuser) Tells the bot to join a named channel
    add_command :debug, "admin channel join" do |message,channels|
      raise "Denied" unless message.user.superuser?
      channels.each do |channel|
        message.network.puts "JOIN #{channel}"
      end
    end

    #@doc
    # (superuser) Tells the bot to join a named channel
    add_command :debug, "admin channel leave" do |message,channels|
      raise "Denied" unless message.user.superuser?
      channels.each do |channel|
        message.network.puts "PART #{channel}"
      end
    end

    #@doc
    # Returns the current loglevel or (superuser) sets it
    add_command :debug, "admin loglevel" do |message, (level)|
      message.reply( if level.nil?
        "System loglevel is currently #{logging.number_to_const[logging.loglevel]}"
      else
        auth_command :superuser, message
        level = level.to_s.upcase.to_sym
        if self.class.constants.include? level
          logging.loglevel = self.class.const_get( level )
          "Okay, logging is now set to #{level}"
        else
          "No such log level #{level}"
        end
      end )
    end

    #@doc
    # Returns whether a named hook is runnable
    # A hook is runnable if it has a code block attached to it that is not disabled
    # Every hook is associated with a feature name; enabled features are stored in the 'allowed_features' setting object on core, networks and channels
    add_command :debug, "admin hook runnable" do |message, (hook)|
      if hook_runnable? hook.to_sym, message
        message.reply "true"
      else
        message.reply "false"
      end
    end

    #@doc
    # (superuser) changes the debug settings for log messages that pass through named functions
    # (Using this will slow the bot down slightly as logging becomes more expensive)
    add_command :debug, "admin log label add" do |message, (label,level)|
      auth_command :superuser, message
      raise "What label?" if label.nil?
      if level
        level = level.to_s.upcase.to_sym
        raise "Invalid debug level #{level}" unless CCCB.instance.debug_levels.include? level
        CCCB.instance.logging.loglevel_by_label ||= {}
        CCCB.instance.logging.loglevel_by_label[label] = level
      end

      level = (CCCB.instance.logging.loglevel_by_label||{})[label]
      message.reply "Logging for #{label} is set to #{level.inspect}"
    end

    #@doc
    # (superuser) Remove a log level override
    add_command :debug, "admin log label remove" do |message, (label)|
      auth_command :superuser, message
      raise "What label?" if label.nil?
      CCCB.instance.logging.loglevel_by_label ||= {}
      CCCB.instance.logging.loglevel_by_label.delete(label)
      CCCB.instance.logging.loglevel_by_label = nil if CCCB.instance.logging.loglevel_by_label.empty?
      level = (CCCB.instance.logging.loglevel_by_label||{})[label]
      message.reply "Logging for #{label} is set to #{level.inspect}"
    end

    #@doc
    # (superuser) Shuts down the bot immediately
    add_command :debug, "admin kill" do |message|
      auth_command :superuser, message
      persist.store.save
      Thread.list.each do |t|
        next if t == Thread.current
        t.raise "Dai the Death"
      end
      raise "Dai the Death"
    end
  end
end
