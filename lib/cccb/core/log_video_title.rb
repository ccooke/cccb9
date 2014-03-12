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

    add_hook :uri_video_title, :uri_found do |message, uri_data|
      # uri_data is a hash with :uri, :protocol, :before and :after keys

      # next in this block acts as a return would in a method
      next unless message.to_channel?
      next unless match = VIDEO_URI_REGEX.match(uri_data[:uri])
      # If the option isn't set on the user, the code will check the
      # channel, then the network and finally the core for it.
      next unless message.user.get_setting("options", "log_video_title")

      source = match[1]
      id = match[2]
      verbose "Fetching title of #{uri_data[:uri]}"
      title = Mechanize.new.get( uri_data[:uri] ).title.strip.lines.first.chomp
      verbose "And done"
      if /youtu(\.be|be\.com)/.match source
        source = "youtube"
      elsif /vimeo/.match source
        source = "vimeo"
      end

      message.reply "#{source} video: #{title}"
    end
  end
end
