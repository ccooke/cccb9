# Early logging
$early_logging = []
module Kernel
  %i{ critical error warning info verbose debug spam detail}.each_with_index do |sym,i|
    define_method sym do |*message,**keys|
      $early_logging << [sym,message,keys]
    end
  end
end

require 'etc'
require 'managedthreads'
require 'string_format'
require 'module/requirements'
require 'cccb/config'
require 'cccb/core'
require 'cccb/irc'

$load_time = Time.now
$load_errors = []
print_loading = $VERBOSE || $DEBUG;

[ "lib/module/requirements/feature", "lib/cccb/core", "lib/cccb/modules" ].each do |dir|
  Dir.new(dir).select { |f| f.end_with? '.rb' }.each do |file|
    begin
      Kernel.load("#{dir}/#{file}")
    rescue Exception => e
      puts "Failed to load #{dir}/#{file}: #{e.message}"
      $load_errors << "#{dir}/#{file}: #{e.message}"
      next
    end
    puts "Loaded #{dir}/#{file}..." if print_loading
  end
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
      log_level_by_label: args[:log_level_by_label] || nil,
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

  def inspect
    "<#{to_s}:#{networking.networks}>"
  end
end
