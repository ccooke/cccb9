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
      options = { 
        Port: CCCB.instance.get_setting( "http_server", "port" ),
        DoNotReverseLookup: true,
        SSLEnable: true,
        Logger: WEBrick::Log.new(nil,WEBrick::Log::WARN),
        AccessLog: [
          [ 
            CCCB::Logger,
            "WWW %a GET %U -> %s %b bytes"
          ]
        ]
      }
      if cert_file = CCCB.instance.get_setting("http_server", "cert_file")
        options[:SSLCertificate] = OpenSSL::X509::Certificate.new File.read(cert_file)
      end
      if key_file = CCCB.instance.get_setting("http_server", "cert_key")
        options[:SSLPrivateKey] = OpenSSL::PKey::RSA.new File.read(key_file)
      end
      unless options.include? :SSLCertificate and options.include? :SSLPrivateKey
        options.delete( :SSLCertificate )
        options.delete( :SSLPrivateKey )
        options[:SSLCertName] = [ %w{ CN localhost } ]
      end
        
      @@server = WEBrick::HTTPServer.new options
      if @@server
        unless options.include? :SSLCertificate and options.include? :SSLPrivateKey
          Dir.mkdir("conf/ssl") unless Dir.exists?("conf/ssl")
          File.write("conf/ssl/auto_generated.cert", @@server.ssl_context.cert.to_s)
          File.write("conf/ssl/auto_generated.key", @@server.ssl_context.key.to_s)
          CCCB.instance.set_setting("conf/ssl/auto_generated.cert","http_server","cert_file")
          CCCB.instance.set_setting("conf/ssl/auto_generated.key","http_server","cert_key")
        end
        break
      end
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
    network = nil

    if match = %r{^(?<cp>/network/(?<network>[^/]+))(?<path>.*)$}.match( req.path )
      debug "Req.path #{req.path.inspect} replace with #{match[:path]}"
      req.path.replace match[:path].to_s
      if req.path == ""
        req.path.replace "/status"
      end
      network = cccb.networking.networks[match[:network]]
      raise "No such network" if network.nil?

      session_cookie = req.cookies.find { |c| c.name == match[:cp] }
      if session_cookie.nil?
        session = nil
      else
        key = req.remote_ip + ':' + session_cookie.value
        session = CCCB.instance.get_setting( "web_sessions", key )
      end

      if session.nil?
        sid = SecureRandom.uuid
        key = req.remote_ip + ':' + sid
        info "New (or expired) session #{key}"
        session = OpenStruct.new
        CCCB.instance.set_setting( session, "web_sessions", key )
        res.cookies << WEBrick::Cookie.new( match[:cp], sid )
      end
    else
      session = OpenStruct.new
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
        
				block.call( network, session, match, req, res )
        return
			end
		end
		raise WEBrick::HTTPStatus::NotFound
	end

	def self.add_path( regex, send = :path, &block )
		@@blocks << [send,regex,block]		
	end

  def self.add_keyword_path( keyword, &block )
    add_path %r{^/#{keyword}(?:/(?<call>.*))?$}, :path do |network,session,match,req,res|
      hash = block.call(network, session, match)
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
    add_setting :core, "web_sessions", persist: false
    default_setting 9000, "http_server", "port"
    default_setting "http://localhost:9000", "http_server", "url"
    default_setting 15, "web", "session_expire"

    begin
      CCCB::ContentServer.restart
    rescue Exception => e
      error "Error starting content server: #{e} #{e.backtrace}"
    end

    ManagedThread.new :clean_web_sessions, repeat: 60, start: true, restart: true do 
      run = Time.now
      CCCB.instance.networking.networks.each do |name, network|
        expiry = network.get_setting( "web", "session_expire" ).to_f
        sessions = CCCB.instance.get_setting("web_sessions")
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

    CCCB::ContentServer.add_keyword_path('status') do |network,session,match,req,res|
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
