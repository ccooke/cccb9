require 'dbi'
require 'net/http'
require 'mechanize'

module CCCB::Core::Links
  extend Module::Requirements

  def links_process_line (message)
    return nil unless message.user.get_setting( "options", "log_links" )
    urlre = /(\b((?:https?|ftp):\/\/|www\.)[-a-zA-Z0-9~`\!@#\$%^&*\(\)-_=+|\\\[\]\{\};:'",<.>\/\?]+)(.*)/i
    imgre = /(jpe?g|bmp|png|gif)$/i
    vidre = /(youtube.com\/watch.*v=|youtu.be\/|vimeo.com\/)(.*?)(&|$)/i

    if message.to_channel?
      nick = message.nick
      channel = message.replyto
          
      if (m = urlre.match(message.text))
        url = m[1]
        proto = m[2]
        comment = m[3]
        unless /:/.match (proto)
          url = "http://"+url
        end


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


        if (imgre.match(url)) && message.user.get_setting( "options", "log_links" )
          if /nsfw/i.match (comment)
            nsfw = 1
          else
            nsfw = 0
          end
          q_pic.execute(url,nick,channel,nsfw,comment)
        elsif (m = vidre.match(url))
          source = m[1]
          id = m[2]
          title = Mechanize.new.get( url ).title.strip.lines.first.chomp
          if /youtu(\.be|be\.com)/.match source
            source = "youtube"
          elsif /vimeo/.match source
            source = "vimeo"
          end
          if message.user.get_setting( "options", "log_links" )
            q_vid.execute(id,source,nick,channel,comment,title)
          end
          if message.user.get_setting( "options", "videotitle" )
            message.reply "Video title: #{title}"
          end
        elsif message.user.get_setting( "options", "log_links" )
          q_lnk.execute(url,nick,channel,comment)
        end
        dbh.disconnect
      end
    end
  end

  def module_load
    add_setting :core, "secure", secret: true
    # set on the core object, defaults everyone to on. Users
    # and channels can override
    set_setting true, "options", "log_links"
    set_setting true, "options", "videotitle"

    add_request :links, /^what.*url.*logging.*\s*\?\s*$/ do |message|
      "If you're asking about the URL logging site, it's at http://midnight.blue-infinity.net/f5.php"
    end

    add_hook :links, :message do |message|
      links_process_line message
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
