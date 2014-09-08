require 'managedthreads'

module Module::Requirements::Feature::Logging
  extend Module::Requirements

  @@logging_queue ||= Queue.new

  class Logger
    def self.<<(message)
      info message, tag: "Logger"
    end
  end

  class ThreadLessLog
    define_method :<< do |(level,message,keys)|
      message.each do |m|
        CCCB.instance.debug_print level, m, **keys
      end
    end

    def pop(*args)
      sleep 1
    end

    def empty?
      true
    end
  end

  needs :static_methods

  def caller_map
    string = ""
    caller_locations(2).reverse.each_with_object([]) do |l,a|
      a << ( string += ";#{l.label}:#{l.lineno}" ).dup
    end
  end

  def log?(level)
    log_level = CCCB.instance.logging.loglevel||DEBUG

    if by_level = CCCB.instance.logging.loglevel_by_label
      locations = caller_locations
      return false unless log_level >= level or by_level.any? { |k,v| 
        next unless v.respond_to? :to_sym
        level_for_k = self.class.const_get( v.to_sym )
        locations.any? { |l| 
          #p lo: locations.map(&:label), k: k, L: level_for_k, LEVEL: level if l.label == k
          l.label == k and level_for_k >= level 
        } 
      }
    else
      return false unless log_level >= level
    end
  
    true
  end

  DEBUG_LEVELS = %i( CRITICAL ERROR WARNING INFO VERBOSE DEBUG SPAM DETAIL DETAIL2 DETAIL3 DETAIL4 DETAIL5 )

  def debug_levels
    DEBUG_LEVELS
  end

  @@logging_number_to_const = {}
  DEBUG_LEVELS.each_with_index do |const,index|
    method = const.to_s.downcase.to_sym
    const_set( const, index )
    @@logging_number_to_const[index] = const
    define_method method do |*message, **keys|
      level = self.class.const_get( const )
      tags_to_apply = []
      return unless log?(level)
      tag_sets = Array(Thread.current.thread_variable_get(:logging_tags))
      unless tag_sets.empty?
        locations = caller_map
        tag_sets.pop until tag_sets.empty? or locations.any? { |t| tag_sets.first[:trace] == t }
        tags_to_apply = tag_sets.select { |t| 
          locations.include? t[:trace] 
        }
      end
        
      tags = tags_to_apply.each_with_object([]) do |t,o|
        t[:tags].each do |k,(m,v)|
          str = if v.nil?
            "[#{k}]"
          else
            "[#{k}=#{v}]"
          end
          case m
          when :set
            o << { k: k, v: str, m: m }
          when :replace
            found = 0
            o.reverse.select { |h| h[:k] == k }.each { |h|
              found += 1
              h[:m] = :replace
              h[:v] = str
              break
            }
            o << {k: k, v: str, m: m } if found == 0
          end
        end
      end.map { |h| h[:v] }.join(' ')
      tags += " " unless tags.empty?
      expanded_message = message.map do |string|
        string = "[#{const}] #{tags}#{string}"
      end
      
      Module::Requirements::Feature::Logging.class_variable_get(:@@logging_queue) << [level,expanded_message,keys]

      return *message
    end
  end

  def get_log_id
    [Time.now().to_f].pack("G").unpack("H*").first[9..16]
  end

  def replace_log_tag tag = nil, **tags
    set_log_tag(tag, mode: :replace, **tags)
  end

  def add_log_tag tag = nil, **tags
    set_log_tag(tag, mode: :set, **tags)
  end

  def set_log_tag tag = nil, mode: :set, **tags
    return unless log?(logging.loglevel)
    tags[tag] = "%id%" unless tag.nil?
    tagset = tags.each_with_object({}) do |(k,v),h|
      h[k] = [mode, v]
      next unless v.respond_to? :gsub!
      v.gsub! /%id%/, get_log_id
    end
    unless Thread.current.thread_variable? :logging_tags
      Thread.current.thread_variable_set :logging_tags, []
    end
    Thread.current.thread_variable_get(:logging_tags) << { trace: caller_map[-3], tags: tagset }
  end

  def log( *strings, **keys )
    begin
      strings.each do |string|
        #string = "#{kwargs.keys.map { |k| "#{k}: #{kwargs[k]} " }.join}#{string}" #if logging.tag
        message = sprintf( "[%s] %s",
          Time.now.strftime("%Y-%m-%d %H:%M:%S.%N"),
          string
        )
        logging.logfile.puts message # if self.log_to_file
        logging.logfile.flush
      end
    rescue Exception => e
      puts "DEBUG FAILURE: #{e} #{e.backtrace.inspect}"
    end
  end

  def debug_print level, *msg, **keys
    keys[:level] = @@logging_number_to_const[level]
    log *msg, **keys
  end

  def logging_transition_unthreaded
    old_queue = Module::Requirements::Feature::Logging.class_variable_get(:@@logging_queue)
    logging.log_queue = ThreadLessLog.new
    logging.log_thread.kill if logging.log_thread
    Module::Requirements::Feature::Logging.class_variable_set(:@@logging_queue, logging.log_queue)
    until old_queue.empty?
      logging.log_queue << old_queue.pop
    end
    verbose "Transitioned to unthreaded logging"
  end

  def logging_transition_threaded
    logging.log_queue = Module::Requirements::Feature::Logging.class_variable_set(:@@logging_queue,Queue.new)
    logging.log_thread = Thread.new do
      loop do
        (level,message,keys) = logging.log_queue.pop
        message.each { |m| debug_print level, *m, **keys}
      end
    end
    verbose "Transitioned to threaded logging"
  end

  def module_load
    logging.loglevel ||= self.class.const_get( self.log_level.upcase ) || VERBOSE
    logging.loglevel_by_label ||= self.log_level_by_label || nil
    logging.logfile = File.open( self.logfile, 'a' ) || STDOUT
    global_methods :debug_print, *debug_levels.map(&:to_s).map(&:downcase).map(&:to_sym)
    logging.number_to_const = {}
    @@logging_number_to_const.each do |k,v|
      logging.number_to_const[k] = v
    end

    $early_logging.each do |sym,message,keys|
      self.send(sym,*message,**keys)
    end
    $early_logging.clear

    logging_transition_unthreaded
  end

  def module_start
    logging_transition_threaded
  end

  def module_unload
    logging_transition_unthreaded
  end
end

