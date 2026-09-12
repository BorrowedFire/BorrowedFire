# Extract local-resource destinations without flattening balanced Markdown syntax.
module MarkdownResources
  module_function

  def escaped?(text, index)
    index.positive? && text[0...index][/\\+\z/].to_s.length.odd?
  end

  def unescape(text)
    text.gsub(/\\([[:punct:]])/, '\\1')
  end

  def normalize_label(label)
    unescape(label).strip.gsub(/\s+/, ' ').downcase
  end

  def mask_inline_code(text)
    prose = text.dup
    index = 0
    while (start = text.index('`', index))
      width = text[start..][/\A`+/].length
      index = start + width
      next if escaped?(text, start)
      match = /(?<!`)`{#{width}}(?!`)/.match(text, index)
      next unless match
      index = match.end(0)
      prose[start...index] = text[start...index].gsub(/[^\r\n]/, ' ')
    end
    prose
  end

  def closing(text, start, opener, closer)
    depth = 1
    index = start + 1
    while index < text.length
      char = text[index]
      if char == '\\' && text[index + 1]&.match?(/[[:punct:]]/)
        index += 2
        next
      end
      depth += 1 if char == opener && opener != closer
      depth -= 1 if char == closer
      return index if depth.zero?
      index += 1
    end
    nil
  end

  def whitespace_end(text, start)
    start + text[start..].to_s[/\A\s*/].length
  end

  def destination(text, start)
    if text[start] == '<'
      finish = closing(text, start, '<', '>')
      return nil unless finish
      value = text[(start + 1)...finish]
      return nil if value.include?("\n") || value.include?('<')
      return [value, finish + 1]
    end
    index = start
    depth = 0
    while index < text.length
      char = text[index]
      if char == '\\' && text[index + 1]&.match?(/[[:punct:]]/)
        index += 2
        next
      end
      break if char.match?(/\s/) || (char == ')' && depth.zero?)
      depth += 1 if char == '('
      depth -= 1 if char == ')'
      index += 1
    end
    return nil unless depth.zero?
    [text[start...index], index]
  end

  def inline_link(text, start)
    index = whitespace_end(text, start + 1)
    parsed = destination(text, index)
    return nil unless parsed
    target, finish = parsed
    index = whitespace_end(text, finish)
    if text[index] != ')'
      return nil if index == finish
      opener = text[index]
      return nil unless ['"', "'", '('].include?(opener)
      title_end = closing(text, index, opener, opener == '(' ? ')' : opener)
      return nil unless title_end
      index = whitespace_end(text, title_end + 1)
    end
    return nil unless text[index] == ')'
    return nil if text[start..index].match?(/\n[ \t]*\n/)
    [target, index + 1]
  end

  def definition_end(text, destination_end)
    line_end = text.index("\n", destination_end) || text.length
    title_start = whitespace_end(text, destination_end)
    opener = text[title_start]
    inline_title = !text[destination_end...line_end].strip.empty?
    if ['"', "'", '('].include?(opener) && text[destination_end...title_start].count("\n") <= 1
      title_end = closing(text, title_start, opener, opener == '(' ? ')' : opener)
      if title_end && !text[title_start..title_end].match?(/\n[ \t]*\n/)
        finish = text.index("\n", title_end + 1) || text.length
        return finish if text[(title_end + 1)...finish].strip.empty?
      end
    end
    inline_title ? nil : line_end
  end

  def definitions_and_prose(text)
    definitions = {}
    ranges = []
    text.to_enum(:scan, /^ {0,3}\[/).each do
      start = Regexp.last_match.end(0) - 1
      next if ranges.any? { |range| range.cover?(start) }
      finish = closing(text, start, '[', ']')
      next unless finish && text[finish + 1] == ':'
      label = text[(start + 1)...finish]
      next if normalize_label(label).empty? || label.match?(/\n[ \t]*\n/)
      target_start = whitespace_end(text, finish + 2)
      next if text[(finish + 2)...target_start].count("\n") > 1
      parsed = destination(text, target_start)
      next unless parsed && !parsed[0].empty?
      line_end = definition_end(text, parsed[1])
      next unless line_end
      definitions[normalize_label(label)] ||= parsed[0]
      ranges << (start...line_end)
    end
    prose = text.dup
    ranges.reverse_each { |range| prose[range] = ' ' * (range.end - range.begin) }
    [definitions, prose]
  end

  def scan_links(text, definitions)
    targets = []
    index = 0
    while index < text.length
      unless text[index] == '[' && !escaped?(text, index)
        index += 1
        next
      end
      finish = closing(text, index, '[', ']')
      unless finish
        index += 1
        next
      end
      label = text[(index + 1)...finish]
      if label.match?(/\n[ \t]*\n/)
        index += 1
        next
      end
      after = finish + 1
      parsed = inline_link(text, after) if text[after] == '('
      if parsed
        target, after = parsed
      else
        reference_start = after
        reference_end = closing(text, reference_start, '[', ']') if text[reference_start] == '['
        if reference_end
          reference = text[(reference_start + 1)...reference_end]
          target = definitions[normalize_label(reference.empty? ? label : reference)]
          after = reference_end + 1 if target
        end
        target ||= definitions[normalize_label(label)]
      end
      nested = label.include?('[') ? scan_links(label, definitions) : []
      image = index.positive? && text[index - 1] == '!' && !escaped?(text, index - 1)
      if target && image
        # Link-like text inside image alt text does not load another resource.
        targets << {target: target, image: true}
      else
        if target && nested.any? { |node| !node[:image] }
          target = nil
          after = finish + 1
        end
        targets << {target: target, image: false} if target
        targets.concat(nested)
      end
      index = after
      target = parsed = reference_end = nil
    end
    targets
  end

  def targets(text)
    definitions, prose = definitions_and_prose(text)
    scan_links(prose, definitions).map { |node| unescape(node[:target]) }
  end
end
