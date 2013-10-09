require 'webrick'
require 'webrick/https'
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

    delay = 1
    10.times do
      @@server = WEBrick::HTTPServer.new(
        Port: CCCB.instance.get_setting( "http_server", "port" ),
        DoNotReverseLookup: true,
        SSLEnable: true,
        SSLCertName: [ %w{ CN localhost } ],
        AccessLog: [
          [ 
            CCCB::Logger,
            "WWW %a GET %U -> %s %b bytes"
          ]
        ]
      )
      break if @@server
      error "HTTP server did not start - sleeping a few seconds before retrying"
      sleep delay
      delay *= 2
    end
    

    @@server.mount '/static', WEBrick::HTTPServlet::FileHandler, "#{CCCB.instance.basedir}/web/static/"
		@@server.mount_proc '/' do |req, res|
			CCCB::ContentServer.request( req, res )
		end

		@@thread = Thread.new do
			@@server.start
		end
	end

	def self.request(req,res)
    cccb = CCCB.instance
    session = nil

    if match = %r{^(?<cp>/network/(?<network>[^/]+))(?<path>.*)$}.match( req.path )
      debug "Req.path #{req.path.inspect} replace with #{match[:path]}"
      req.path.replace match[:path].to_s
      if req.path == ""
        req.path.replace "/status"
      end
      network = cccb.networking.networks[match[:network]]
      raise "No such network" if network.nil?

      session_cookie = req.cookies.find { |c| c.name == match[:cp] }
      key = req.remote_ip + ':' + session_cookie.value
      session = network.get_setting( "web_sessions", key )

      if session.nil?
        sid = SecureRandom.uuid
        key = req.remote_ip + ':' + sid
        info "New (or expired) session #{key}"
        session = OpenStruct.new
        network.set_setting( session, "web_sessions", key )
        res.cookies << WEBrick::Cookie.new( match[:cp], sid )
      end

      session.network = network
    else
      session = OpenStruct.new
      session.network = false
    end

    session.addr = req.remote_ip
    session.time = Time.now

		@@blocks.each do |(send,matcher,block)|
			match_object = if send == nil
				req
			else
				req.send(send)
			end
			if match = matcher.match( match_object )
				block.call( session, match, req, res )
        return
			end
		end
		raise WEBrick::HTTPStatus::NotFound
	end

	def self.add_path( regex, send = :path, &block )
		@@blocks << [send,regex,block]		
	end

  def self.add_keyword_path( keyword, &block )
    add_path %r{^/#{keyword}(?:/(?<call>.*))?$}, :path do |network,match,req,res|
      hash = block.call(network, match)
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
    add_setting :core, "http_server"
    add_setting :core, "web"
    add_setting :network, "web"
    add_setting :network, "web_sessions", persist: false
    set_setting( 9000, "http_server", "port" ) unless get_setting( "http_server", "port" )
    set_setting( "http://localhost:9000", "http_server", "url" ) unless get_setting( "http_server", "url" )
    set_setting( 15, "web", "session_expire" ) unless get_setting( "http_server", "session_expire" )

    begin
      CCCB::ContentServer.restart
    rescue Exception => e
      error "Error starting content server: #{e} #{e.backtrace}"
    end

    ManagedThread.new :clean_web_sessions, repeat: 60, start: true, restart: true do 
      run = Time.now
      CCCB.instance.networking.networks.each do |name, network|
        expiry = network.get_setting( "web", "session_expire" ).to_f
        sessions = network.get_setting("web_sessions")
        sessions.each do |sid, session|
          if session.time + expiry < run 
            info "Expire session #{sid}"
            sessions.delete(sid)
          end
        end
      end
    end

    CCCB::ContentServer.add_keyword_path('test') do |m| 
      {
        template: :plain_text,
        text: :OK
      }
    end

    CCCB::ContentServer.add_keyword_path('debug') do |m| 
      {
        template: :plain_text,
        text: PP.pp( {
          cccb: CCCB.instance,
          store: Module::Requirements.instance_variable_get(:@storage)
        }, "" )
      }
    end

    CCCB::ContentServer.add_keyword_path('status') do |session,match,req,res|
      {
        title: "Status for #{session.network.name}",
        blocks: [
          [ :content,
            "<pre>" + CGI::escapeHTML(session.to_json) + "</pre>"
          ]
        ]
      }
    end
  end
end
