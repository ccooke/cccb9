
class CCCB::Reply
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
    { text: [ self.summary || self.title || self.fulltext ].flatten }
  end

  def short_form
    { 
      title: [ *self.title ].first, 
      text: [ self.summary || self.fulltext ]
    }
  end

  def long_form
    {
      title: [ *self.title ].first,
      text: [ self.fulltext || self.summary ]
    }
  end
    
end

module CCCB::Core::Reply
  extend Module::Requirements

end
