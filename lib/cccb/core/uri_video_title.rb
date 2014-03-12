require 'mechanize'

module CCCB::Core::URIVideoTitle
  # This is mandatory. Loads in the dependency resolution code
  extend Module::Requirements

  VIDEO_URI_REGEX = /(youtube.com\/watch.*v=|youtu.be\/|vimeo.com\/)(.*?)(&|$)/i

  # The list of dependencies. Almost anything that you are likely
  # to write will depend on :bot. This module depends on :links 
  # because it will process uri events
  needs :bot, :links

  # Every module defines a module_load. These methods will be called
  # in dependency-resolution order (so the CCCB::Core::Bot and 
  # CCCB::Core::Links module_load methods will have been called before
  # this
  
  def module_load
    # Set the core dictionary "options" key "log_video_title" to true
    # but only if it is not yet set.
    default_setting true, "options", "log_video_title"

    # Every module has its own storage area. This is named after the 
    # module (converted to snake_case). Data saved to it will be
    # automatically saved and loaded from the bot's state directory
    # module_load should default any values in case the state is cleared
    uri_video_title.history ||= []

    # AVOID USING @instance VARIABLES. Your module will be loaded into
    # the CCCB core object instance; two modules using the same @instance
    # variable name would be very easy. Use the namespaced OpenStruct
    # instead.

    add_hook :uri_video_title, :uri_found do |message, uri_data|
      # uri_data is a hash with :uri, :protocol, :before and :after keys

      # next in this block acts as a return would in a method
      next unless message.to_channel?
      next unless match = VIDEO_URI_REGEX.match(uri_data[:uri])
      # If the option isn't set on the user, the code will check the
      # channel, then the network and finally the core for it.
      next unless message.user.get_setting("options", "log_video_title")

      source = match[1]
      title = Mechanize.new.get( uri_data[:uri] ).title.strip.lines.first.chomp
      if /youtu(\.be|be\.com)/.match source
        source = "youtube"
      elsif /vimeo/.match source
        source = "vimeo"
      end

      # Send a reply to the message...
      message.reply "#{source} video: #{title}"
      # And store the uri in our history
      uri_video_title.history << [ message.nick, source, uri_data[:uri], title ]
      uri_video_title.history.shift if uri_video_title.history.count > 1024
    end

    add_request :uri_video_title, /^link search (?<pattern>.*?)\s*$/ do |match, message|
      pattern = Regexp.escape(match[:pattern])
      pattern.gsub! /%/, '.*'
      regex = Regexp.new(pattern)
      seen = {}
      uri_video_title.history.select { |(n,s,u,title)| 
        regex.match title 
      }.each do |(nick, source, uri, title)|
        next if seen.include? uri
        message.reply "from #{nick} [#{title}]: #{uri}"
        seen[uri] = true
      end
      nil # requests automatically respond with whatever the block returns
          # ending with nil prevents this
    end
  end
end
