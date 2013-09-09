
module CCCB::Client::Core::UserCode
  needs :hooks

  def load_user_code(codedir)
    @hooks = {}
    add_hook :exception do |e|
      error e.message
      debug e.backtrace.inspect
    end
    Dir.new(codedir).sort.each do |file|
      next unless file =~ /\.rb$/
      code = File.read(codedir + '/' + file )
      @source = file
      begin
        code_file = codedir + '/' + file
        if $".include? code_file
          info "Reloading hook: #{ file }"
          $".delete( code_file )
        else
          info "Loading hook: #{ file }"
        end
        Kernel.load( code_file )
      rescue Exception => e
        # "(eval):9:in `block (2 levels) in load_hooks'"
        error_string = "ERROR in #{file}: (#{e}): #{ $!.inspect }"
        /^\(eval\):(\d+):in \`block \((\d+) levels\) in load_hooks'/.match( e.backtrace[0] ) do |m|
          error_string = "ERROR in #{file} line #{m[1]}: #{ $!.inspect }"
        end
        e.message.replace error_string
        begin
          @hooks[:exception].each do |saviour|
            saviour[:code].call( e )
          end
        end
      end
    end
  end
  def module_init
    
  end
end


