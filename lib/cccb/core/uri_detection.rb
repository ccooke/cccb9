
module CCCB::Core::URIDetection
  extend Module::Requirements

  URL_REGEX = /((([A-Za-z]{3,9}:(?:\/\/)?)(?:[\-;:&=\+\$,\w]+@)?[A-Za-z0-9\.\-]+|(?:www\.|[\-;:&=\+\$,\w]+@)[A-Za-z0-9\.\-]+)((?:\/[\+~%\/\.\w\-_]*)?\??(?:[\-\+=&;%@\.\w_]*)#?(?:[\.\!\/\\\w]*))?)/

  def module_load
    default_setting(true, "options", "uri_events")

    add_hook :uri_detection, :message do |message|
      next unless message.user.get_setting( "options", "uri_events" )
      text = message.text
      while match = URL_REGEX.match( text )
        schedule_hook :uri_found, message, {
          uri: match[1],
          protocol: match[3] || "http://",
          before: match.pre_match,
          after: match.post_match
        }
        text = match.post_match
      end
    end

  end
end
