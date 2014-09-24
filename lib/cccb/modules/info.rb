module CCCB::Core::InfoBot
  extend Module::Requirements
  needs :bot, :uri_detection

  def module_load
    add_setting :core, "info"
    add_setting :network, "info"
    add_setting :channel, "info"

    add_command :info, "info" do |message, args|
      text = if args[1] == '='
        target = message.to_channel? ? :channel : :network
        user_setting message, "#{target}::info::#{args[0]}", args[2]
      elsif args[0] and value = message.get_setting("info", args[0])
        value
      elsif args[0]
        "No idea"
      else
        "#{CCCB.instance.get_setting("http_server","url")}/network/#{message.network}/info"
      end
      message.reply text
    end

    CCCB::ContentServer.add_keyword_path('info') do |network,session,match|
      factoids = {}
      factoids["These things I hold to be universally true"] = CCCB.instance.get_setting("info")
      factoids["On #{network}, I believe that"] = network.nil? ? {} : network.get_setting("info")
      channel_info = network.channels.each do |name,channel|
        factoids["In #{name}"] = channel.get_setting("info")
      end

      {
        title: "Information I know",
        blocks: [
          [ :content,
            factoids.reject { |k,v| v.empty? }.map { |(k,v)|
              "<h1>#{k}</h1><p>#{ 
                v.map { |n,f| 
                  text = "<p><h2>#{CGI::escapeHTML(n)}</h2> is &#147;#{CGI::escapeHTML(f)}&#148;</p>"
                  text.gsub CCCB::Core::URIDetection::URL_REGEX do |url|
                    "<a href=\"#{url}\">#{url}</a>"
                  end
                }.join("\n")
              }</p>"
            }.join("<hr/>\n")
          ]
        ]
      }
    end
  end
end
