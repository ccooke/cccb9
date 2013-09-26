module Module::Requirements::Feature::Events
  extend Module::Requirements

  class Event < OpenStruct
    class InvalidEvent < Exception; end
    REQUIRED = [
      :start_time,
      :hook,
      :name
    ]
    def initialize(hash = {})
      raise InvalidEvent.new(hash) unless REQUIRED.all? { |k| hash.include? k }
      super(hash)
    end
  end

  needs :hooks, :managed_threading

  def add_timer(frequency, &block)
    auto_timer_hook = :"auto_timer_#{block.object_id}"

    events.lock.synchronize do
      add_hook :events, auto_timer_hook, block
      add_event frequency: frequency, hook: auto_timer_hook, name: auto_timer_hook, start_time: Time.now + frequency
    end

    auto_timer_hook
  end

  def add_event(*args)
    events.lock.synchronize do
      events.db << Event.new(args)
      debug "Added event: #{events.db.last}"
      events.db = sort_events
    end
  end

  def sort_events
    events.db.sort do |a,b|
      a.start_time <=> b.start_time
    end
  end

  def module_start
    events.lock ||= Mutex.new
    events.db ||= []
    ManagedThread.new :events, start: true, repeat: 1, restart: true do
      events.lock.synchronize do
        time = Time.now
        spam "Events since #{time}: #{events.db}"
        while events.db.count > 0 and events.db.first.start_time <= time
          event = events.db.shift
          debug "Got event #{info}"
          schedule_hook event.hook, event
          if event.recurrs
            event.start_time += event.frequency while event.start_time <= time
            events.db << event
          end
          
          events.db = sort_events
        end
      end
    end
  end

end
