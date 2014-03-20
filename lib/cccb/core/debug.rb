module CCCB::Core::Debugging
  extend Module::Requirements

  needs :bot, :commands

  def module_load
    add_command :debug, "set hook trace" do |message, hooks|
      default_setting true, "allowed_features", "debug_hook_trace"
      target = if message.to_channel? 
        message.channel
      else
        message.user
      end
      result = []
      hooks.map(&:to_sym).each do |h|
        message.reply("Adding debug hook to #{h}")
        add_hook :debug_hook_trace, h do |*args|
          target.msg "<debug: hook=#{h} args=#{args.inspect}>"
        end
        result << "Trace hooks for #{h}: #{get_hooks( :debug_hook_trace, h )}"
      end
    end

    add_command :debug, "unset hook trace" do |message, hooks|
      hooks.map(&:to_sym).each do |h|
        trace_hooks = get_hooks( :debug_hook_trace, h )
        trace_hooks.each do |tr_h|
          message.reply("Removing debug hook from #{h}")
          remove_hook(:debug_hook_trace, h, tr_h[:source_file], tr_h[:source_line])
        end
      end
    end
  end
end
