module CCCB::Core::Pom
  extend Module::Requirements
  needs :bot

  def module_load
    add_command :pom, "pom" do |message|
      message.reply %x{pom}
    end

    add_command :ebook, "ebook add" do |message, args|
      if message.user.get_setting( "privs", "allow_fanfic" )
        %x{fanfic-fetch #{args[0]}}.each_line do |line|
          message.reply line
        end
      else
        message.reply "You need the allow_fanfic privilege"
      end
    end
  end
end
