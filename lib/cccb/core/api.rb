require 'cgi'
require 'json'

module CCCB::Core::APICore
  extend Module::Requirements

  needs :bot

  def register_api_method(feature,method,&block)
    method_name = :"#{feature}.#{method}"
    hook_name = :"api/#{method_name}"
    debug "Adding API method #{method_name}"
    add_hook feature, hook_name, generator: 2, unique: true do |return_queue, **args|
      detail2 "Hook #{hook_name} called for #{method}"
      detail2 "Return #{return_queue}, args: #{args}"
      args[:method_name] = method_name
      args[:method] = method
      result = block.call(**args)
      detail2 "Returned: #{result}"
      return_queue << result
    end
  end

  def api(method, timeout: 30, **args)
    unless args.include? :__message
      network = networking.networks.values.first
      message = CCCB::Message.new( network, ":API PRIVMSG d20 :#{method} #{args.inspect}" )
      args[:__message] = message
    end

    hook_name = :"api/#{method}"
    raise "No such API method: #{method}" unless hooks.db.include? hook_name
    return_queue = Queue.new
    detail "API Request: #{hook_name}(#{args}), timeout #{timeout}, return #{return_queue}"
    start = Time.now
    if hooks.runners == 0
      detail2 "Running #{hook_name} locally since there are no hook_runners"
      run_hooks hook_name, return_queue, **args
    else
      detail2 "Scheduling #{hook_name} (There are #{hooks.runners} hook runners)"
      schedule_hook hook_name, return_queue, **args
    end
    detail "Returned from hook"
    loop do
      return return_queue.pop unless return_queue.empty?
      if Time.now - start > timeout
        raise "Timeout waiting for #{hook_name}"
      end
    end
  end

  def module_load
    register_api_method :debug, :echo do |**args|
      detail "debug.echo called with args: #{args}"
      args[:string]
    end

    servlet = Proc.new do |network, session, match, request|
      debug "Got call: #{request}"

      params = CGI::parse(request.query_string).each_with_object({}) do |(k,v),h| 
        h[k.to_sym] = v.last
      end
      method = match[:call].split('/').first
      params[:__message] = CCCB::Message.new( network, ":WEB PRIVMSG d20 :#{request.request_line}" )

      debug "API call from web: #{method.inspect}, #{params.inspect}"
      begin
        text = {
          method: method,
          result: api(method, **params)
        }
      rescue Exception => e
        text = {
          method: method,
          error: e.message,
          exception: e.class,
        }
      end
      debug "Returned: #{text.inspect}"
      {
        template: :plain_text,
        text: text.to_json
      }
    end

    CCCB::ContentServer.add_keyword_path('api',&servlet)
  end

  def module_test
    test_string = "Testing #{rand}"
    raise "API is broken" unless api("debug.echo", string: test_string) == test_string
  end

end
