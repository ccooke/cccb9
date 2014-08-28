# encoding: utf-8
module CCCB::Core::Tables
  extend Module::Requirements

  needs :bot, :dice

  def gen_table_result(message, table_name, modifier=0, recursion=0)
    raise "Too many nested tables detected at #{table_name}" if recursion > 20
    table = message.user.get_setting("tables", table_name) || if message.to_channel?
      message.channel.get_setting("tables", table_name)
    end
    raise "No such table: #{table_name}" if table.nil?
    raise "Empty table" unless table[:entries].count > 0 

    value = if table.include? :expression
      parser = Dice::Parser.new(table[:expression], default: "1d20")
      parser.roll
      parser.value
    else
      max_entry = table[:entries].max_by { |(r,d)| r.max }
      max_num = max_entry[0].max
      SecureRandom.random_number( max_num ) + 1
    end

    value += modifier || 0
    
    table[:entries].select { |(r,d)| r.include? value }.map { |r,d| gen_table_entry( message, d, recursion + 1 ) }.each do |result|
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
      message.reply result
    end
    nil
  end

  def gen_table_entry( message, entries, recursion )
    unless entries.respond_to? :count
      entries = [ [ entries, "entry" ] ]
    end

    entries.map do |entry, type, modifier|
      case type
      when "entry"
        entry 
      when "link"
        gen_table_result( message, entry, modifier, recursion )
      end
    end
  end

  def module_load
    add_setting :user, "tables"
    add_setting :channel, "tables"
    add_setting :network, "tables"
    add_setting :core, "tables"

    add_request :tables, /^\s*table\s+(?<table>\w+)\s*$/ do |match, message|
      table = match[:table]
    end

    add_request :tables, /^\s*(?<command>create|destroy|open|close)\s+(?:(?<target>core|network|channel|user)\s+)?table\s+(?<table>\w+)\s*$/ do |match, message|
      target = if match[:target]
        match[:target]
      else 
        if message.to_channel?
          :channel
        else
          :user
        end
      end

      container = message.send(target)
      raise "Denied: You are not allowed to modify tables in the #{target} class" unless container.auth_setting( message, "tables" )

      case match[:command]
      when "create","open"
        table = container.get_setting("tables", match[:table]) || {
          entries: {}
        }
        message.user.set_setting table, "session", "__user_current_table"
        if container.get_setting("tables", match[:table]).nil?
          container.set_setting( table, "tables", match[:table] )
          "Created #{match[:table]}"
        else
          "Opened #{match[:table]}"
        end
      when "destroy"
        container.set_setting( nil, "tables", match[:table] )
        message.user.set_setting nil, "session", "__user_current_table"
        "Deleted #{match[:table]}"
      when "close"
        message.user.set_setting nil, "session", "__user_current_table"
        "Ok"
      end
    end

    add_request :tables, /^(?<command>add|remove|show) table expression(?: (?<expression>.*))?/ do |match, message|
      table = message.user.get_setting( "session", "__user_current_table" )
      raise "Open a table first" unless table

      
      case match[:command]
      when "add"
        Dice::Parser.new( match[:expression], default: "1d20" )
        table[:expression] = match[:expression]
      when "show"
        "Current expression: #{table[:expression] || "(auto-generated)"}"
      when "remove"
        table.delete :expression
      end
    end

    add_request :tables, /^(?<command>add|remove|list) table (?<type>entry|link) (?<from>\d+)(?:-(?<to>\d+))?(?: (?<data>.*?))?\s*$/ do |match, message|
      table = message.user.get_setting( "session", "__user_current_table" )
      raise "Open a table first" unless table

      from = match[:from].to_i
      to = (match[:to] || match[:from]).to_i
      raise "Invalid range" if to < from

      range = (from..to)

      target = :entries

      table[target] ||= {}
      case match[:command]
      when "add"
        table[target][range] ||= []
        table[target][range] << [ match[:data], match[:type] ]
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
        "Deleted #{count} #{match[:type]}s"
      end
    end

    add_request :tables, /^gen (?<table>\w+)(?:\s+(?<modifier>\d+))?$/ do |match, message|
      gen_table_result message, match[:table], match[:modifier].to_i 
    end
  end
end
