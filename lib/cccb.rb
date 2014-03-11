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

print_loading = $VERBOSE || $DEBUG;

Dir.new("lib/cccb/core").select { |f| f.end_with? '.rb' }.each do |file|
  begin
    Kernel.load("lib/cccb/core/#{file}")
  rescue LoadError => e
    puts "Failed to load #{file}: #{e.message}"
    next
  end
  puts "Loaded #{file}..." if print_loading
end


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
      log_level: args[:log_level] || "VERBOSE",
      user: args[:user] || Etc.getlogin,
      nick: args[:nick] || Etc.getlogin,
      servers: args[:servers],
      userstring: args[:userstring] || "An extendable ruby bot",
      superuser_password: args[:superuser_password] || nil,
      basedir: args[:basedir],
      statedir: statedir,
      logfile_tag: args[:logfile_tag], 
      logfile: args[:logfile] || args[:basedir] + '/logs/cccb.log',
    }
  end

  def to_s
    "CCCB"
  end
end
