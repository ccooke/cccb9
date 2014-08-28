module CCCB::Core::InfoBot
  extend Module::Requirements
  needs :bot

  def module_load
    add_setting :core, "info"
    add_setting :network, "info"
    add_setting :channel, "info"

    add_command :info, "info" do |message, args|
      text = if args[1] == '='
        target = message.to_channel? ? :channel : :network
        user_setting message, target, "info", args[0], args[2]
      elsif value = message.get_setting("info", args[0])
        value
      else
        "No idea"
      end
      message.reply text
    end
  end
end
