require 'dbi'
require 'net/http'
require 'mechanize'

module CCCB::Core::Links
  extend Module::Requirements

  needs :bot, :uri_detection

  def links_process_line (message, uri_data)
    imgre = /(jpe?g|bmp|png|gif)$/i
    vidre = /(youtube.com\/watch.*v=|youtu.be\/|vimeo.com\/)(.*?)(&|$)/i

    nick = message.nick
    channel = message.replyto
        
    begin
      info "Connect to DB"
      dbh = DBI.connect(
        CCCB.instance.get_setting( "secure", "midnight_db_dbi" ),
        CCCB.instance.get_setting( "secure", "midnight_db_user" ),
        CCCB.instance.get_setting( "secure", "midnight_db_password" ),
      )
      info "Connected to DB"
      q_pic = dbh.prepare("INSERT INTO image (link,poster,channel,NSFW,comment,date) VALUES (?,?,?,?,?,NOW())")
      q_lnk = dbh.prepare("INSERT INTO link (link,poster,channel,comment,date) VALUES (?,?,?,?,NOW())")
      q_vid = dbh.prepare("INSERT INTO video (id,source,poster,channel,comment,title,date) VALUES (?,?,?,?,?,?,NOW())")
    rescue DBI::DatabaseError => e
      warning "Unable to connect to database: #{e}"
      return nil
    end

    if (imgre.match(uri_data[:uri]))
      if [:before,:after].any? { |t| uri_data[t].match /nsfw/i }
        nsfw = 1
      else
        nsfw = 0
      end
      q_pic.execute(uri_data[:uri],nick,channel,nsfw,uri_data[:after])
    elsif (m = vidre.match(uri_data[:uri]))
      source = m[1]
      id = m[2]
      title = Mechanize.new.get( uri_data[:uri] ).title.strip.lines.first.chomp
      if /youtu(\.be|be\.com)/.match source
        source = "youtube"
      elsif /vimeo/.match source
        source = "vimeo"
      end
      q_vid.execute(id,source,nick,channel,uri_data[:after],title)
      if message.user.get_setting( "options", "videotitle" )
        message.reply "Video title: #{title}"
      end
    else 
      q_lnk.execute(uri_data[:uri],nick,channel,uri_data[:after])
    end
    dbh.disconnect
  end

  def module_load
    add_setting :core, "secure", secret: true
    # set on the core object, defaults everyone to on. Users
    # and channels can override
    options = get_setting("options")
    options["uri_events"] = true unless options.include? "uri_events"
    options["log_links"] = true unless options.include? "log_links"
    options["videotitle"] = true unless options.include? "videotitle"

    add_request :links, /^what.*url.*logging.*\s*\?\s*$/ do |message|
      "If you're asking about the URL logging site, it's at http://midnight.blue-infinity.net/f5.php"
    end

    add_hook :links, :uri_found do |message, uri_data|
      next unless message.to_channel?
      next unless message.user.get_setting( "options", "log_links" )
      links_process_line message, uri_data
    end

    add_help(
      :links,
      "links",
      "Links, images and videos are collected on a webpage",
      [
        "The bot collects links, images and videos onto webpages.",
        "They can be found at http://midnight.blue-infinity.net/f5.php",
        "Users can disable and enable link collection for URLs they put on",
        "channel by sending a 'CTCP LOGLINKS <off/on>' command to the bot.",
        "This module is maintained by snow."
      ]
    )
  end
end
