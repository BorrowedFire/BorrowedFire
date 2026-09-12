#!/usr/bin/env ruby
# Validate the skill files and local links that an installed entrypoint exposes.
require 'yaml'
require 'json'
require 'pathname'
require 'uri'
require 'tmpdir'
require 'fileutils'
require_relative 'markdown-resources'

json_output = ARGV.delete('--json')
copy_layout = ARGV.delete('--copy-layout')
roots = ARGV.empty? ? [File.expand_path('../skills', __dir__)] : ARGV
errors = []
skills = []
roots.each do |root|
  path = File.expand_path(root)
  if File.file?(path) && File.basename(path) == 'SKILL.md'
    skills << path
  elsif File.file?(File.join(path, 'SKILL.md'))
    skills << File.join(path, 'SKILL.md')
  elsif File.directory?(path)
    Dir.children(path).sort.each do |name|
      candidate = File.join(path, name, 'SKILL.md')
      skills << candidate if File.file?(candidate)
      errors << "#{path}/#{name}: dangling skill link" if File.symlink?(File.join(path, name)) && !File.exist?(File.join(path, name))
    end
  else
    errors << "#{path}: skill root does not exist"
  end
end
errors << 'No skill entrypoints found' if skills.empty?

copy_boundary = nil
if copy_layout
  staging = Dir.mktmpdir('skill-copy-validation-')
  at_exit { FileUtils.remove_entry(staging) if File.exist?(staging) }
  copy_boundary = File.join(staging, 'skills')
  FileUtils.mkdir_p(copy_boundary)
  skills = skills.map do |path|
    if File.symlink?(File.dirname(path))
      errors << "#{path}: copied skill roots must be directories, not symlinks"
      next nil
    end
    destination = File.join(copy_boundary, File.basename(File.dirname(path)))
    if File.exist?(destination)
      errors << "#{path}: duplicate skill name in copied layout"
      next nil
    end
    # Match install.sh: copy each skill directory, not loose files beside it.
    begin
      FileUtils.cp_r(File.dirname(path), destination, dereference_root: true)
    rescue SystemCallError => e
      errors << "#{path}: cannot stage copied skill (#{e.class})"
      next nil
    end
    File.join(destination, 'SKILL.md')
  end.compact
  copy_boundary = File.realpath(copy_boundary)
end

checked_links = 0
visited = {}
check_links = lambda do |path|
  canonical = File.realpath(path)
  if copy_boundary && !canonical.start_with?(copy_boundary + File::SEPARATOR)
    errors << "#{path}: resource escapes the copied skill layout"
    return
  end
  return if visited[canonical]
  visited[canonical] = true
  text = File.read(canonical, encoding: 'UTF-8')
  # Fenced examples are not declarations of installed resources.
  fence = nil
  prose = text.each_line.map do |line|
    if fence
      closing = /\A {0,3}#{Regexp.escape(fence[0])}{#{fence.length},}[ \t]*\r?\n?\z/
      fence = nil if line.match?(closing)
      line.gsub(/[^\r\n]/, ' ')
    elsif (opening = line.match(/\A {0,3}(`{3,}|~{3,})[^\r\n]*\r?\n?\z/))
      fence = opening[1]
      line.gsub(/[^\r\n]/, ' ')
    else
      line
    end
  end.join
  # Inline code can contain a Markdown example intended for a future product file.
  links_prose = MarkdownResources.mask_inline_code(prose)
  targets = MarkdownResources.targets(links_prose).map { |target| [target, false] }
  targets += prose.scan(%r{`((?:/Users|/home)/[^`\n]+)`}).flatten.map { |target| [target, true] }
  targets.uniq.each do |target, literal_path|
    next if target.start_with?('#') || target.match?(/\A[a-z][a-z0-9+.-]*:/i)
    # Root-relative URLs describe a product route. Explicit home paths describe local files.
    next if target.start_with?('/') && !target.start_with?('/Users/', '/home/')
    # Split URL components before decoding: %3F and %23 are literal filename bytes.
    target = URI::DEFAULT_PARSER.unescape(target.split(/[?#]/, 2).first.to_s) unless literal_path
    next if target.empty?
    checked_links += 1
    resolved = File.expand_path(target, File.dirname(canonical))
    unless File.exist?(resolved)
      errors << "#{canonical}: missing local resource #{target}"
      next
    end
    if copy_boundary && File.realpath(resolved) != copy_boundary &&
       !File.realpath(resolved).start_with?(copy_boundary + File::SEPARATOR)
      errors << "#{canonical}: local resource escapes the copied skill layout: #{target}"
      next
    end
    check_links.call(resolved) if File.file?(resolved) && File.extname(resolved) == '.md'
  end
rescue SystemCallError, ArgumentError, EncodingError => e
  errors << "#{path}: #{e.class}: #{e.message}"
end

skills.uniq.each do |path|
  text = File.read(path, encoding: 'UTF-8')
  match = text.match(/\A---\r?\n(.*?)\r?\n---(?:\r?\n|\z)/m)
  if match.nil?
    errors << "#{path}: missing YAML frontmatter"
    next
  end
  begin
    data = YAML.safe_load(match[1], permitted_classes: [], permitted_symbols: [], aliases: false)
    unless data.is_a?(Hash) && data['name'].is_a?(String) && !data['name'].strip.empty? &&
           data['description'].is_a?(String) && !data['description'].strip.empty?
      errors << "#{path}: name and description must be nonempty YAML strings"
    end
  rescue Psych::Exception => e
    errors << "#{path}: invalid YAML (#{e.class})"
  end
  check_links.call(path)
rescue SystemCallError, ArgumentError, EncodingError => e
  errors << "#{path}: #{e.class}: #{e.message}"
end

result = { skills: skills.uniq.length, resources: visited.length, links: checked_links, errors: errors }
if json_output
  puts JSON.pretty_generate(result)
else
  errors.each { |error| warn "ERROR: #{error}" }
  puts "Validated #{result[:skills]} skills and #{checked_links} local links: #{errors.length} errors"
end
exit(errors.empty? ? 0 : 1)
