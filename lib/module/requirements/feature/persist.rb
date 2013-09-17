require 'yaml'

module Module::Requirements::Feature::Persist
  extend Module::Requirements

  needs :events, :static_methods

  class PersistException < Exception; end

  class Storage
    def define(klass, key)
      raise PersistException.new("Persistant storage can only be added to Class objects") unless klass.is_a? Class
      persist.lock.synchronize do
        persist.data[klass.name] ||= {}
        persist.data[klass.name][:key] = key
        persist.data[klass.name][:data] ||= {}
        klass.class_exec(key,persist.data) do |k,store|
          define_method :storage do 
            store[self.class.name][:data][self.send(k)] ||= {}
          end
        end
      end
    end
  end

  class FileStore < Storage
    def initialize(dir)
      @dir = dir
    end

    def load
      raise PersistException.new("Unable to read from #{@dir}") unless Dir.exists? @dir and File.writable? @dir 
      persist.lock.synchronize do
        Dir.open(@dir).each do |f|
          next if f.start_with? '.' or ! f.end_with? '.db'
          loaded = YAML.load( File.read( "#{@dir}/#{f}" ) )
          debug "Loaded data for #{loaded[:class]}"
          persist.data[loaded[:class]] = loaded[:data]
        end
      end
    end

    def save
      raise PersistException.new("Unable to store in #{@dir}") unless Dir.exists? @dir and File.writable? @dir 
      persist.lock.synchronize do
        persist.data.each do |klass,store|
          begin
            debug "Storing persist data for #{klass}"
            File.open( "#{@dir}/#{klass}.db.tmp", 'w' ) do |f|
              stringified = { :class => klass, :data => store }.to_yaml
              f.puts stringified
              spam "Written #{stringified.length} bytes"
            end
            File.rename "#{@dir}/#{klass}.db.tmp", "#{@dir}/#{klass}.db"
          end
        end
      end
    end

  end

  needs :events

  def module_load
    global_methods :persist

    persist.lock ||= Mutex.new
    persist.store ||= FileStore.new(".")
    persist.data ||= {}
  end

  def module_start
    persist.store.load

    ManagedThread.new :storage_checkpoint, repeat: 60, start: true, restart: true do
      debug "Running storage checkpoint"
      persist.store.save
    end
  end

  def module_unload
    ManagedThread[:storage_checkpoint].stop
    persist.store.save
  end

end
