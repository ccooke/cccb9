module CCCB::Core::Tables
  extend Module::Requirements

  needs :bot, :dice

  def module_load
    add_setting :user, "tables"
    add_setting :channel, "tables"
    add_setting :network, "tables"
    add_setting :core, "tables"

    add_request :tables, /^\s*table\s+(?<table>\w+)\s*$/ do |match, message|
      table = match[:table]
      
    end

    add_request :tables, /^\s*(?<command>create|destroy|open|close)\s+(?:(?<target>core|network|channel|user)\s+)?table\s+(?<table>\w+)\s*$/ do |match, message|
      target = if message.user.superuser? and match[:target]
        match[:target]
      elsif [ :user, :channel ].any? { |t| match[:target] == t }
        match[:target]
      elsif match[:target].nil?
        if message.to_channel?
          :channel
        else
          :user
        end
      else
        raise "Denied: You are not allowed to modify tables in the #{match[:target]} class"
      end

      container = message.send(target)
      case match[:command]
      when "create","open"
        table = container.get_setting("tables", match[:table]) || {
          entries: {}
        }
        message.user.set_setting table, "session", "__user_current_table"
        unless container.setting?("tables", match[:table])
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

    add_request :tables, /^(?<command>add|remove|show) table entry (?<from>\d+)(?:-(?<to>\d+))?(?: (?<data>.*?))?\s*$/ do |match, message|
      table = message.user.get_setting( "session", "__user_current_table" )
      raise "Open a table first" unless table

      from = match[:from].to_i
      to = (match[:to] || match[:from]).to_i
      raise "Invalid range" if to < from

      range = (from..to)
      table[:entries] ||= {}
      case match[:command]
      when "add"
        table[:entries][range] = match[:data]
      when "show"
        table[:entries].map do |r,d|
          "#{r}: #{d}"
        end
      when "remove"
        count = 0
        table[:entries].keys.select { |k| k.all? { |kv| range.include? kv } }.each do |key|
          table[:entries].delete(key)
          count += 1
        end
        "Deleted #{count} entries"
      end
    end

    add_request :tables, /^gen (?<table>\w+)(?:\s+(?<modifier>\d+))?$/ do |match, message|
      table = message.user.get_setting("tables", match[:table]) || if message.to_channel?
        message.channel.get_setting("tables", match[:table])
      end
      raise "No such table: #{match[:table]}" if table.nil?
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

      table[:entries].select { |(r,d)| r.include? value }.map { |r,d| d }
    end
  end
end
