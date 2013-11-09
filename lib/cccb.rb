require 'etc'
require 'managedthreads'
require 'string_format'
require 'module/requirements'
require 'module/requirements/feature/reload'
require 'module/requirements/feature/managed_threading'
require 'module/requirements/feature/hooks'
require 'module/requirements/feature/logging'
require 'module/requirements/feature/call_module_methods'
require 'module/requirements/feature/staticmethods'
require 'module/requirements/feature/events'
require 'module/requirements/feature/persist'
require 'cccb/config'
require 'cccb/core'
require 'cccb/irc'
require 'cccb/core/filter_hooks'
require 'cccb/core/usercode'
require 'cccb/core/bot'
require 'cccb/core/networking'
require 'cccb/core/settings'
require 'cccb/core/httpserver'
require 'cccb/core/help'
require 'cccb/core/choice'
require 'cccb/core/dice'
require 'cccb/core/hugs'
require 'cccb/core/links'
require 'cccb/core/public_logs'
require 'cccb/core/session'
require 'cccb/core/ops'
require 'cccb/core/packages'
require 'cccb/core/yarn'
require 'cccb/core/pom'
require 'cccb/core/auto-reconnect'

class String
  include String::Keyreplace
end

class CCCB 

  VERSION = "9.0-pre1"
  
  include CCCB::Core
  include CCCB::Config

  @@instance ||= nil

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
    statedir = args[:statedir] || args[:basedir] + '/conf/state/'
    persist.store = Module::Requirements::Feature::Persist::FileStore.new( statedir ) 
    logging.tag = args[:logfile_tag]

    {
      log_to_file: args[:log_to_file] || true,
      log_to_stdout: args[:log_to_stdout] || true,
      user: args[:user] || Etc.getlogin,
      nick: args[:nick] || Etc.getlogin,
      servers: args[:servers],
      userstring: args[:userstring] || "An extendable ruby bot",
      debug_privmsg: args[:debug_privmsg] || "#cccb-debug}",
      superuser_password: args[:superuser_password] || nil,
      basedir: args[:basedir],
      statedir: statedir,
      codedir: args[:codedir] || args[:basedir] + '/lib/cccb/usercode',
      logfile_tag: args[:logfile_tag], 
      logfile: args[:logfile] || args[:basedir] + '/logs/cccb.log',
      botpattern: args[:botpattern] || /^cccb/,
    }
  end

  def to_s
    "CCCB"
  end
end
