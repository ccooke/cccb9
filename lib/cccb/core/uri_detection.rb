
module CCCB::Core::URIDetection
  extend Module::Requirements

  needs :bot

  URL_REGEX = /
    (?<uri>
      (?<protocol>
        \p{Word}+
        :
        (?:
          \/\/
        )?
      )?
      (?<server>
        (?:
          \p{Word}+
          @
        )?
        \p{Word}+
        (?<domain>
          \.
          \p{Word}+
        )*
        (?:
          : 
          \d+
        )?
      )
      (?<path>
        (?:
          \/
          [\p{Word}%]+
        )*
        (?:
          (?:
            \?
          |
            #
          )
          \S+
        )*
      )?
    )
  /x

  def module_load
    begin
      default_setting(true, "options", "uri_events")
    rescue Exception => e
      verbose e
      verbose e.backtrace
    end

    add_hook :uri_detection, :message do |message|
      debug("In uri detection")
      text = message.text
      next unless message.user.get_setting( "options", "uri_events" )
      while match = URL_REGEX.match( text )
        text = match.post_match
        next if match[:server].nil? or match[:domain].nil? || ( match[:protocol].nil? && match[:path] == "" )
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
