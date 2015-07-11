
module CCCB::Core::URIDetection
  extend Module::Requirements

  needs :bot

  URL_REGEX = /
    (?<protocol> \p{Word}+ : (?: \/\/)?){0}
    (?<server> (?: \p{Word}+ @)?  \p{Word}+ (?<domain> \.  \p{Word}+)* (?: : \d+)?){0}
    (?<path> \/ [\p{Word}.%]+ (?: (?: \?  | \#) \S+)* ){0}

    (?<uri> 
      \g<protocol> \g<server> \g<path>*
    | 
      \g<server> \g<path>+
    )
  /x

  def module_load
    begin
      default_setting(true, "options", "uri_events")
    rescue Exception => e
      verbose e
      verbose e.backtrace
    end
  
    #@doc
    # Detects URIs and calls the 'uri_found' hook on each one
    add_hook :uri_detection, :message do |message|
      text = message.text
      next unless message.user.get_setting( "options", "uri_events" )
      while match = URL_REGEX.match( text )
        text = match.post_match
        schedule_hook :uri_found, message, {
          uri: match[:uri],
          protocol: match[:protocol] || "http://",
          before: match.pre_match,
          after: match.post_match,
        }
      end
    end

  end
end
