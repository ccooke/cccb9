gem 'redcarpet' #, '<=3.2.0'
require 'redcarpet'

class CCCB::Reply
  class IRCRender < Redcarpet::Render::Base
    COLOURS = {
      white:        '00',
      black:        '01',
      blue:         '02',
      green:        '03',
      red:          '04',
      brown:        '05',
      purple:       '06',
      orange:       '07',
      yellow:       '08',
      light_green:  '09',
      teal:         '10',
      cyan:         '11',
      light_blue:   '12',
      pink:         '13',
      grey:         '14',
      light_grey:   '15',
      default:      '99'
    }

    COLOURS.each do |k,v|
      define_method(k) do |text|
        "\x03#{v}#{text}\x03"
      end
    end

    def normal_text(text)
      text
    end

    def block_code(code,language = nil)
      block = if language 
        title = code
        code = language
        [ "|== #{italic title} ==", ] 
      else
        []
      end
      block += normal_text(code).each_line.map do |l|
        l.gsub /^    /, '| '
      end
      block.join("\n") + "\n"
    end

    def codespan(code)
      code
    end

    def self.strip_formatting(string)
      return "" if string.nil?
      string = string.gsub /\x030?\d\d([^\x03\x0f]*)(?:\x03|\x0f)/, '\1'
      string.gsub /\x02|\x06|\x16|\x1f/, ''
    end

    def bold(text)
      "\x02#{text.gsub(/x02/,"")}\x02"
    end
    
    def reverse(text)
      "\x16#{text.gsub(/x16/,"")}\x16"
    end
    
    def italic(text)
      "\x06#{text.gsub(/x06/,"")}\x06"
    end
    
    def underline(text)
      "\x1f#{text.gsub(/x1f/,"")}\x1f"
    end

    def highlight(text)
      reverse(text)
    end

    def quote(text)
      '"' + text + '"'
    end

    def header(title,level)
      case level
      when 1 then text = underline(bold(title))
      when 2 then text = underline(title)
      when 3 then text = reverse(title)
      when 4 then text = italic(title)
      else
        text = title
      end
      text + "\n"
    end

    def hrule(*args)
      info "Hrule: #{args}"
      "------------------------------------\n"
    end

    def superscript(text)
      text
    end

    def strikethrough(text)
      text.chars.map { |c| "#{c}\u0336" }.join
    end

    def triple_emphasis(text)
      bold underline text
    end

    def double_emphasis(text)
      bold text
    end

    def emphasis(text)
      italic text
    end
    
    def linebreak
      " \n"
    end
    
    def paragraph(text)
      text + "\n"
    end
    
    def list(content,list_type)
      "\u0000L[#{content}\u0000L]"
    end
    
    def list_item(content, list_type)
      type = list_type.to_s[0]
      "\u0000L#{type}#{content}\u0000L}"
    end
    
    def link(link,title,content)
      light_blue(underline(content))
    end
    alias_method :autolink, :link

    def postprocess(data)
      lists = []
      indent = [ 0 ]
      parsed = ""
      prefix = nil
      until ( index = data.index("\u0000") ).nil?
        indent_str = " " * indent.last
        data[0,index].each_line do |l|
          if prefix
            parsed += prefix + l
            prefix = nil
          else
            parsed += indent_str + l
          end
        end
        token = data[index+1,2]
        data[0,index+3] = ""
        case token
        when "L["
          lists << { index: 1 }
          indent << indent.last + 2
        when "L]"
          lists.pop
          indent.pop
        when "Lu"
          prefix = "* "
        when "Lo"
          lo = "#{lists.last[:index]}. "
          prefix = lo
          indent.last += lo.length - 2
          lists.last[:index] += 1
        when "L}"
        end
      end
      parsed + data
    end

    def table(header, rowdata)
      header.gsub!(/\u0000t$/,"")
      rows = [ header, *rowdata.scan(/(.*?)\u0000t/).flatten ]
      table = []
      rows.each do |r|
        row = []
        table << row
        r.scan(/(.*?)\u0000T/).flatten.each_with_index do |c,i|
          stripped = CCCB::Reply::IRCRender.strip_formatting(c)
          row << [ c, stripped.length ]
        end
      end
      output = ""
      width = []
      table.each_with_index do |r,n|
        row = []
        r.each_with_index do |c,i|
          width[i] ||= table.map { |tr| tr[i][1] }.max.to_f
          content, length = c
          content = bold(content) if n == 0
          pad = (width[i] - length) / 2
          row << " " * pad.ceil + content + " " * pad.floor
        end
        output += "|" + row.join("|") + "|\n"
      end
      output
    end

    def table_row(*args)
      #info("TR: #{args.inspect}")
      args[0] + "\u0000t"
    end

    def table_cell(*args)
      #info("TC: #{args.inspect}")
      "#{args[0]}\u0000T"
    end
    
    def footnotes(*args)
      info "Ignored: :footnotes #{args}"
    end

    def footnotes_def(*args)
      info "Ignored: :footnotes_def #{args}"
    end

    def footnotes_ref(*args)
      info "Ignored: :footnotes_ref #{args}"
    end

    def respond_to?(sym)
      #info "#{self}.respond_to?(#{sym.inspect})"
      true # super
    end

    def method_missing(sym,*args,**kwargs,&block)
      info "#{self}.#{sym}(*#{args.inspect},**#{kwargs.inspect},&#{block})"
      args[0]
    end
  end

  @categories = %i{ title summary fulltext }

  def initialize(message)
    @message = message
    @no_minimal = false
  end

  @categories.each do |sym|
    attr_accessor sym
    writer = :"#{sym}="
    var = :"@#{sym}"
    define_method sym do |data = nil|
      if data
        self.send(writer,data)
        self
      else
        self.instance_variable_get(var)
      end
    end
  end

  def append(text)
    self.summary = "#{self.summary}#{text}"
    self.fulltext = "#{self.fulltext}#{text}"
    text
  end

  def write
    @message.send_reply
  end

  def no_minimal
    @no_minimal = true
  end

  def force_title=(title_text)
    self.no_minimal
    self.title = title_text
  end

  def minimal_form
    return self.short_form if @no_minimal
    [ self.summary || self.title || self.fulltext ].flatten.join("\n")
  end

  def short_form
    "# #{[ *self.title ].first}\n#{self.summary || self.fulltext}"
  end

  def long_form
    if not self.title.nil?
      "# #{[ *self.title ].first}\n"
    else
      ""
    end + "#{self.fulltext || self.summary}"
  end
    
end

module CCCB::Core::Reply
  extend Module::Requirements

  KEYWORD = /^ (?<keyword> \w+ ) (?: : (?<argument> .* ) )? $/x

  def markdown_list(list)
    list.map do |i|
      if i.is_a? Array
        markdown_list(i).force_encoding("UTF-8").gsub(/^(\s*)\*/m,'  \1*')
      else
        "* #{i}"
      end
    end.join("\n")
  end

  def keyword_expand(string, message, loop_count: 0)
    return string if loop_count > 10
    string.keyreplace do |key|
      if match = KEYWORD.match(key.to_s) 
        if reply.keywords.include? match[:keyword]
          replacement = reply.keywords[match[:keyword]].call( match[:argument], message )
          keyword_expand( replacement.to_s, message, loop_count: loop_count + 1 )
        else
          "«Unknown expansion: #{string}»"
        end
      end
    end
  end

  def add_keyword_expansion(name, &block)
    reply.keywords[name.to_s] = block
  end

  def module_load
    reply.keywords = {}

    reply.irc_parser = Redcarpet::Markdown.new( 
      CCCB::Reply::IRCRender,
      no_intra_emphasis: true,
      lax_spacing: true,
      quote: true,
      footnotes: true,
      tables: true,
      highlight: true,
      superscript: true,
      strikethrough: true,
      underline: true
    )
    reply.web_parser = Redcarpet::Markdown.new( 
      Redcarpet::Render::HTML, 
      no_intra_emphasis: true,
      lax_spacing: true,
      quote: true,
      footnotes: true,
      tables: true,
      highlight: true,
      superscript: true,
      strikethrough: true,
      autolink: true,
      underline: true
    )
  end

end
