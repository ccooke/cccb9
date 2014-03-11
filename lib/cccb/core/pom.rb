module CCCB::Core::Pom
  extend Module::Requirements
  needs :bot

  def module_load
    add_request :pom, /^pom$/i do |m, s|
      %x{pom}
    end

    add_request :ebook, /^add fanfic (?<url>.*)/i do |match,message|
      if message.user.get_setting( "privs", "allow_fanfic" )
        %x{fanfic-fetch #{match[:url]}}.each_line do |line|
          message.reply line
        end
      else
        "You need the allow_fanfic privilege"
      end
    end
  end
end
