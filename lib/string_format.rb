module String::Keyreplace
  KEYWORD_REGEX = /(?:|[^%])(%\((\w+)\))/

  def keyreplace! &block
    while match = self.match( KEYWORD_REGEX )
      offsets = match.offset( 1 )
      replacement = block.call( match[2].to_sym ) || ""
      self[ offsets[0] ... offsets[1] ] = replacement
    end
    self
  end

  def keyreplace &block
    self.clone.keyreplace! &block
  end

end
