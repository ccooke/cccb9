require 'redcarpet'

class CCCB::Reply
  class IRCRender < Redcarpet::Render::Base
    def normal_text(text)
      text
    end
    def block_code(code,language = nil)
      block = if language 
        [ "|== #{bold code} ==", ] 
      else
        []
      end
      block += normal_text(code).each_line.map do |l|
        l.strip.gsub /^/, '| '
      end
      block.join("\n")
    end
    def codespan(code)
      block_code(code,nil)
    end
    def bold(text)
      "\x02#{text}\x02"
    end
    def header(title,level)
      ("[" * level) + bold(title) + ("]" * level) + "\n"
    end
    def double_emphasis(text)
      bold text
    end
    def emphasis(text)
      bold text
    end
    def linebreak(text)
      "\n"
    end
    def paragraph(text)
      text + "\n"
    end
    def list(content,list_type)
      index = 0
      content.split("\x03").map do |i|
        case list_type
        when :ordered
          index += 1
          "#{index}. #{i}"
        when :unordered
          "* #{i}"
        end
      end.join("\n") + "\n"
    end
    def list_item(content, list_type)
      "#{content}\x03"
    end
    def link(link,title,content)
      content
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
    "# #{[ *self.title ].first}\n#{self.fulltext || self.summary}"
  end
    
end

module CCCB::Core::Reply
  extend Module::Requirements

  def module_load
    reply.irc_parser = Redcarpet::Markdown.new( 
      CCCB::Reply::IRCRender,
      no_intra_emphasis: true,
      lax_spacing: true,
      quote: false,
      footnotes: false,
      tables: true
    )
    reply.web_parser = Redcarpet::Markdown.new( 
      Redcarpet::Render::HTML, 
      autolink: true,
      footnotes: true,
      tables: true
    )
  end

end
