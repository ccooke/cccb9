# encoding: utf-8
module CCCB::Core::Tables
  extend Module::Requirements

  needs :bot, :dice

  def gen_table_result(message, table_name, modifier=0, recursion=0)
    raise "Too many nested tables detected at #{table_name}" if recursion > 20
    prefix = ""
    container = if table_name.include? '::'
      match = /^(?<channel>.*?)::(?<table>.*)$/.match( table_name )
      table_name = match[:table]
      prefix = match[:channel] + "::"
      message.network.get_channel("##{match[:channel]}")
    elsif message.to_channel?
      message.channel
    elsif message.user.setting? "tables", table_name
      message.user
    else
      raise "I can't find a valid object for that table"
    end
    table = container.get_setting("tables",table_name)
    raise "No such table: #{table_name}" if table.nil?
    raise "Empty table" unless table[:entries].count > 0 

    max_entry = table[:entries].max_by { |(r,d)| r.max }
    max_num = max_entry[0].max
    value = if table.include? :expression

      parser = Dice::Parser.new(table[:expression], default: "1d20")
      parser.roll
      parser.value
    else
      SecureRandom.random_number( max_num ) + 1
    end

    value += modifier || 0
    value = value > max_num ? max_num : value

    table[:entries].select { |(r,d)| r.include? value }.map { |r,d| gen_table_entry( message, d, recursion + 1, prefix ) }.each do |result|
      result.map! do |string|
        if string.respond_to? :gsub
          string.gsub /(%(?<char>.))/ do |match|
            case match
            when '%r'
              value
            when '%%'
              '%'
            end
          end
        else
          string
        end
      end
    end
  end

  def gen_table_entry( message, entries, recursion, prefix )
    unless entries.respond_to? :count
      entries = [ [ entries, "entry" ] ]
    end

    entries.map do |entry, type, modifier|
      case type
      when "entry"
        entry 
      when "link"
        (entry, modifier) = entry.split
        gen_table_result( message, prefix + entry, modifier.to_i, recursion )
      end
    end
  end

  def module_load
    add_setting :user, "tables"
    add_setting :channel, "tables"
    add_setting :network, "tables"
    add_setting :core, "tables"

    add_command :tables, [ %w{ create destroy open close }, [ 'core', 'network', 'channel', 'user', '' ], "table" ] do |message, args, words|
      command = words[1]
      target = if words[2] == 'table'
        if message.to_channel?
          :channel
        else
          :user
        end
      else
        words[2]
      end.to_sym
      table_name = args[0]
      
      container = message.send(target)
      raise "Denied: You are not allowed to modify tables in the #{target} class" unless container.auth_setting( message, "tables" )

      message.reply case command
      when "create","open"
        table = container.get_setting("tables", table_name) || {
          entries: {}
        }
        message.user.set_setting table, "session", "__user_current_table"
        if container.get_setting("tables", table_name).nil?
          container.set_setting( table, "tables", table_name )
          "Created #{table_name}"
        else
          "Opened #{table_name}"
        end
      when "destroy"
        container.set_setting( nil, "tables", table_name )
        message.user.set_setting nil, "session", "__user_current_table"
        "Deleted #{table_name}"
      when "close"
        message.user.set_setting nil, "session", "__user_current_table"
        "Ok"
      end
    end

    add_command :tables, [ %w{add remove show}, 'table', 'expression' ] do |message, args, (ignored, command_name)|
      table = message.user.get_setting( "session", "__user_current_table" )
      raise "Open a table first" unless table
      expression = args.join(' ')
      
      message.reply case command_name
      when "add"
        Dice::Parser.new( expression, default: "1d20" )
        table[:expression] = expression
      when "show"
        "Current expression: #{table[:expression] || "(auto-generated)"}"
      when "remove"
        table.delete :expression
      end
    end

    add_command :tables, [ %w{add remove list}, 'table', %w{entry link} ] do |message, args, (ignored, command_name, _table, type)|
      table = message.user.get_setting( "session", "__user_current_table" )
      raise "Open a table first" unless table
      match = args[0].match( /(?<from>\d+)(?:-(?<to>\d+))?/ ) or raise "Invalid range: #{args[0]}"
      args.shift
      data = args.join(' ')

      from = match[:from].to_i
      to = (match[:to] || match[:from]).to_i
      raise "Invalid range" if to < from

      range = (from..to)

      target = :entries

      table[target] ||= {}
      message.reply case command_name
      when "add"
        table[target][range] ||= []
        table[target][range] << [ data, type ]
      when "list"
        table[target].select { |r,d| range.to_a.any? { |i| r.include? i } }.map do |r,d|
          "#{r}: #{d}"
        end
      when "remove"
        count = 0
        table[target].keys.select { |k| k.all? { |kv| range.include? kv } }.each do |key|
          table[target].delete(key)
          count += 1
        end
        "Deleted #{count} #{type}s"
      end
    end

    add_command :tables, [ %w{genstring} ] do |message, (table,modifier)|
      result =  gen_table_result( message, table, modifier.to_i )
      message.reply.summary = result.flatten.join(" ")
    end

    add_command :tables, [ %w{gen generate} ] do |message, (table,modifier)|
      result =  gen_table_result( message, table, modifier.to_i )
      if result.flatten.count > 2
        message.reply.force_title = "Table: #{table} (+#{modifier})"
      else
        message.reply.title = "Table: #{table} (+#{modifier})"
      end
      message.reply.summary = markdown_list(result)
    end
  end
end
