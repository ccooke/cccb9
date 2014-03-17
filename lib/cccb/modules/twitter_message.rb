require 'mechanize'

module CCCB::Core::TwitterMessage

  extend Module::Requirements

  TWITTER_REGEX = /twitter.com\/(?<name>[A-Za-z0-9_]*)\//i

  needs :bot, :links

  def module_load

    default_setting true, "options", "log_twitter_message"

    twitter_message.history ||= []

    add_hook :twitter_message, :uri_found do |message, uri_data|

      next unless message.to_channel?
      next unless match = TWITTER_REGEX.match(uri_data[:uri])

      # Return the given twitter link, then load the meta_refresh 
      # (mobile) page.
      agent = Mechanize.new
      mobile_url = agent.get(uri_data[:uri]).meta_refresh[0].href
      mobile_page = agent.get(mobile_url)

      name = match[:name]
      tweet = mobile_page.search('.main-tweet .tweet-content .tweet-text div').text
      date = mobile_page.search('.main-tweet .tweet-content .metadata a').text

      message_reply = "twitter \x0311|\x0F #{tweet} \x0311|\x0F tweeted by @#{name} at #{date}"
      message.reply message_reply

      next unless message.user.get_setting("options", "log_twitter_message")

      twitter_message.history << [message.nick, uri_data[:uri], name, date, tweet]
      twitter_message.history.shift if twitter_message.history.count > 1024
    end

    add_request :twitter_message, /^link search (?<pattern>.*?)\s*$/ do |match, message|
      pattern = Regexp.escape(match[:pattern])
      pattern.gsub! /%/, '.*'
      regex = Regexp.new(pattern, true)
      seen = {}
      twitter_message.history.select { |(n,u,name, date, tweet)| 
        regex.match(name) || regex.match(date) || regex.match(tweet)
      }.each do |(nick, uri, name, date, tweet)|
        next if seen.include? uri
        message.reply "from #{nick} \x0311|\x0F #{uri} \x0311|\x0F @#{name} \x0311|\x0F @#{date} \x0311|\x0F @#{tweet}"
        seen[uri] = true
      end
      nil # requests automatically respond with whatever the block returns
          # ending with nil prevents this
    end
  end
end
