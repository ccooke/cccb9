module CCCB::Core::InfoBot
  extend Module::Requirements
  needs :bot

  def module_load
    add_setting :core, "info"
    add_setting :network, "info"
    add_setting :channel, "info"

    add_command :info, "info" do |message, args|
      if args[1] == '='
        target = if message.to_channel?
          message.channel
        else
          message.network
        end
        target.set_setting(args[2], "info", args[0])
        message.reply "Done"
      else
        if value = message.get_setting("info", args[0])
          message.reply value
        else
          message.reply "No idea"
        end
      end
    end
  end
end
