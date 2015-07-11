module CCCB::Core::AutoCut
  extend Module::Requirements
  
  def module_load
    default_setting 512, "options", "auto_cut_length"
    default_setting 20, "options", "auto_cut_context"
    default_setting false, "options", "auto_cut_verbose"

    #@doc
    # If the `auto_cut_length` setting is set on the current channel, checks for messages that long (default: 512) and warns the user their message may have cut off.
    add_hook :autocut, :message do |message|
      next unless message.to_channel?
      max_length = message.channel.get_setting("options", "auto_cut_length").to_i
      if message.raw.length >= max_length
        context = message.channel.get_setting("options", "auto_cut_context").to_i
        string = message.raw.chomp.slice(0 - context, context)

        message.reply "#{message.nick}: Your message might have cut off at '#{string}'"
        message.send_reply
        message.clear_reply
      end

      if message.channel.get_setting("options", "auto_cut_verbose") 
        message.reply "#{message.nick}: Your message is #{message.raw.length} bytes long"
        message.send_reply
        message.clear_reply
      end

      next
    end
  end
end

