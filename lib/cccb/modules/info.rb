module CCCB::Core::InfoBot
  extend Module::Requirements
  needs :bot

  def module_load
    add_setting :core, "info"
    add_setting :network, "info"
    add_setting :channel, "info"

    add_command :info, "info" do |message, args|
      if args[1] == '='
        target = message.to_channel? ? :channel : :network
        message.reply user_setting( message, target, "info", args[0], args[2] )
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
