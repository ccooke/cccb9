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
      agent.user_agent_alias = 'Linux Firefox'
      uri = uri_data[:uri].gsub(/mobile\.twitter\.com/,'twitter.com')

      page = agent.get(uri)

      tweet = page.search('.tweet-text').first.text
      date = page.search('.client-and-actions .metadata span').first.text
      name = page.search('.js-action-profile-name b').first.text

      message_reply = "twitter \x0311|\x0F #{tweet} \x0311|\x0F tweeted by @#{name} at #{date}"
      message.reply message_reply

      next unless message.user.get_setting("options", "log_twitter_message")

      twitter_message.history << [message.nick, uri_data[:uri], name, date, tweet]
      twitter_message.history.shift if twitter_message.history.count > 1024
    end

    add_command :twitter_message, "link search" do |message, args|
      pattern = Regexp.escape(args.join(' '))
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
    end
  end
end
