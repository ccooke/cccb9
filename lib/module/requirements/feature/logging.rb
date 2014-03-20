require 'managedthreads'

module Module::Requirements::Feature::Logging
  extend Module::Requirements

  @@logging_queue ||= Queue.new

  class Logger
    def self.<<(message)
      info message
    end
  end

  class ThreadLessLog
    define_method :<< do |(level,*message)|
      debug_print level, *message
    end

    def pop(*args)
      sleep 1
    end
  end

  needs :static_methods

  %i( CRITICAL ERROR WARNING INFO VERBOSE DEBUG SPAM ).each_with_index do |const,index|
    method = const.to_s.downcase.to_sym
    const_set( const, index )
    define_method method do |*message|
      level = self.class.const_get( const )
      Module::Requirements::Feature::Logging.class_variable_get(:@@logging_queue) << [level,*message]
    end
  end
  
  def log( *strings )
    begin
      strings.each do |string|
        string = "#{logging.tag} #{string}" if logging.tag
        message = sprintf( "[%s] %s",
          Time.now.strftime("%Y-%m-%d %H:%M:%S"),
          string
        )
        logging.logfile.puts message # if self.log_to_file
        logging.logfile.flush
      end
    rescue Exception => e
      puts "DEBUG FAILURE: #{e} #{e.backtrace.inspect}"
    end
  end

  def debug_print level, *msg
    log *msg if (logging.loglevel||DEBUG) >= level
  end

  def module_load
    logging.loglevel ||= self.class.const_get( self.log_level.upcase ) || VERBOSE
    logging.log_queue = ThreadLessLog.new
    logging.logfile = File.open( self.logfile, 'a' ) || STDOUT
    global_methods :critical, :error, :warning, :info, :verbose, :debug, :spam, :debug_print
  end

  def module_start
    logging.log_queue = Module::Requirements::Feature::Logging.class_variable_get(:@@logging_queue)
    logging.log_thread = Thread.new do
      loop do
        (level,message) = logging.log_queue.pop
        message.each_line { |m| debug_print level, m }
      end
    end
    debug "Transitioning to threaded logging"
  end

  def module_unload
    old_queue = logging.log_queue
    logging.log_thread.kill
    logging.log_queue = ThreadLessLog.new
    until old_queue.empty?
      logging.log_queue << old_queue.pop
    end
    debug "Transitioned to unthreaded logging"
  end
end

