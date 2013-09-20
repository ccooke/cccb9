require 'webrick'
require 'erb'
require 'ostruct'
require 'cgi'

class ErbalT < OpenStruct
  def self.render_from_hash(t, h)
    ErbalT.new(h).render(t)
  end

  def render(template)
    ERB.new(template).result(binding)
  end
end

class CCCB::ContentServer
	
	@@blocks = []
  @@keywords = {}
	@@thread ||= nil
	@@server ||= nil
	
	def server
		@@server
	end

	def self.restart
		ObjectSpace.each_object do |o|
			o.shutdown if o.class == WEBrick::HTTPServer
		end

		@@thread.kill if @@thread.respond_to? :kill

		@@server = WEBrick::HTTPServer.new(
			Port: CCCB.instance.get_setting( "http_server", "port" ),
			DoNotReverseLookup: true,
      AccessLog: [
        [ 
          CCCB::Logger,
          "WWW %a GET %U -> %s %b bytes"
        ]
      ]
		)
    

    @@server.mount '/static', WEBrick::HTTPServlet::FileHandler, "#{CCCB.instance.basedir}/web/static/"
		@@server.mount_proc '/' do |req, res|
			CCCB::ContentServer.request( req, res )
		end

		@@thread = Thread.new do
			@@server.start
		end
	end

	def self.request(req,res)

		@@blocks.each do |(send,matcher,block)|
			match_object = if send == nil
				req
			else
				req.send(send)
			end
			if match = matcher.match( match_object )
				block.call( match, req, res )
        return
			end
		end
		raise WEBrick::HTTPStatus::NotFound
	end

	def self.add_path( regex, send = :path, &block )
		@@blocks << [send,regex,block]		
	end

  def self.add_keyword_path( keyword, &block )
    add_path %r{^/#{keyword}(?:/(?<call>.*))?$}, :path do |match,req,res|
      hash = block.call(match)
      template = hash[:template] || 'default'
      if template == :plain_text
        res["Content-type"] = "text/plain"
        res.body = hash[:text].to_s
      else
        erb_file = "#{CCCB.instance.basedir}/web/template/#{template}.rhtml"
        res.body = ErbalT::render_from_hash(File.read(erb_file),hash)
      end
    end
  end
end


module CCCB::Core::HTTPServer
  extend Module::Requirements

  needs :logging

  def module_load
    add_setting :core, "http_server", :superuser, {}
    set_setting( "http_server", 9000, "port" ) unless get_setting( "http_server", "port" )
    set_setting( "http_server", "http://localhost:9000/", "url" ) unless get_setting( "http_server", "url" )
    begin
      CCCB::ContentServer.restart
    rescue Exception => e
      error "Error starting content server: #{e} #{e.backtrace}"
    end

    CCCB::ContentServer.add_keyword_path('test') do |m| 
      {
        template: :plain_text,
        text: :OK
      }
    end
  end
end
