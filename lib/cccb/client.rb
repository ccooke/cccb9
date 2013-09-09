require 'cccb/util/managedthreads'
require 'cccb/util/module_requirements'
require 'cccb/util/config'
require 'cccb/client/core'
require 'cccb/client/core/hooks'
require 'cccb/client/core/call_submodules'
require 'cccb/client/core/threading'
require 'cccb/client/core/reload'
require 'cccb/client/core/debug'
require 'cccb/client/core/usercode'
require 'cccb/client/core/staticmethods'
require 'cccb/client/core/irc'
require 'cccb/client/network'
require 'pp'
require 'irb'

require 'socket'

module CCCB::Client::Core::Networking
	provides :networking
	needs :hooks

	def connected?(network)
		@network[name][:state] == :connected
	end

	def net_thread(method, name)
		debug "Starting net_thread #{method} for #{name}"
		loop do
			begin
				@network[name].send(method)
			rescue Exception => e
				schedule_hook :exception, e
			end
		end
	end

	def module_load
		@network = {}
		@queues = {}

		self.servers.each do |name,conf|
      conf[:name] = name.dup
			@network[name] = CCCB::Client::Network.new(conf)

			ManagedThread.new :"networking_recv_#{name}" do
				net_thread :receiver, name
			end
			ManagedThread.new :"networking_send_#{name}" do
				net_thread :sender, name
			end
		end
	end
end

module CCCB

	VERSION = "9.0-pre1"
	
	class Client
		include CCCB::Client::Core
		include CCCB::Util::Config

		@@instance = nil

		def self.new(*args)
			return @@instance unless @@instance.nil?
			obj = super
			@@instance = obj
		end

		def self.instance
			@@instance
		end

		def configure(args)
			@reload = false
			{
        log_to_file: args[:log_to_file] || true,
        log_to_stdout: args[:log_to_stdout] || true,
				user: args[:user] || ENV['USER'],
				nick: args[:nick] || ENV['USER'],
				servers: args[:servers],
				userstring: args[:userstring] || "An extendable ruby bot",
				debug_privmsg: args[:debug_privmsg] || "#cccb-debug}",
				superuser_password: args[:superuser_password] || nil,
				basedir: args[:basedir],
				statedir: args[:statedir] || args[:basedir] + '/conf/state/',
				codedir: args[:codedir] || args[:basedir] + '/lib/cccb/usercode',
				logfile: args[:logfile] || args[:basedir] + '/logs/cccb8.log',
				botpattern: args[:botpattern] || /^cccb/,
			}
		end

		def start
			startup
			loop do 
				verbose "Starting bot #{config :nick} #{VERSION}"
				call_submodules :start
				verbose "Startup complete"
				sleep 1 until @reload
				reload
			end
		end
	end
end
