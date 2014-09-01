module CCCB::Core::Debugging
  extend Module::Requirements

  needs :bot, :commands, :logging

  def module_load
    add_command :debug, "admin trace add" do |message, hooks|
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

    add_command :debug, "admin trace remove" do |message, hooks|
      hooks.map(&:to_sym).each do |h|
        trace_hooks = get_hooks( :debug_hook_trace, h )
        trace_hooks.each do |tr_h|
          message.reply("Removing debug hook from #{h}")
          remove_hook(:debug_hook_trace, h, tr_h[:source_file], tr_h[:source_line])
        end
      end
    end

    add_command :debug, "admin channel leave" do |message,channels|
      raise "Denied" unless message.user.superuser?
      channels.each do |channel|
        message.network.puts "PART #{channel}"
      end
    end

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

    add_command :debug, "admin hook runnable" do |message, (hook)|
      if hook_runnable? hook.to_sym, message
        message.reply "true"
      else
        message.reply "false"
      end
    end

  end
end
