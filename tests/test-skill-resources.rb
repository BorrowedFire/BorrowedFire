#!/usr/bin/env ruby
require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'

class SkillResourcesTest < Minitest::Test
  VALIDATOR = File.expand_path('../tools/validate-skills.rb', __dir__)

  def setup
    @root = Dir.mktmpdir('skill-resources-')
    @source = File.join(@root, 'source', 'review')
    FileUtils.mkdir_p(@source)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def skill(description: 'Review a change.', body: '')
    File.write(File.join(@source, 'SKILL.md'), "---\nname: review\ndescription: #{description}\n---\n#{body}\n")
  end

  def validate(path = @source)
    output, error, status = Open3.capture3('ruby', VALIDATOR, '--json', path)
    assert_empty error
    [JSON.parse(output), status.success?]
  end

  def test_rejects_invalid_yaml_that_line_matching_accepts
    skill(description: 'Run the queue. Routing: review.')
    report, success = validate
    refute success
    assert report['errors'].any? { |error| error.include?('invalid YAML') }
  end

  def test_rejects_missing_shared_dependency
    skill(body: '[Tool registry](../../tools/REGISTRY.md)')
    report, success = validate
    refute success
    assert_equal 1, report['links']
    assert report['errors'].any? { |error| error.include?('missing local resource') }
  end

  def test_follows_real_symlink_install_and_transitive_resources
    FileUtils.mkdir_p(File.join(@source, 'references'))
    File.write(File.join(@source, 'references', 'guide.md'), '[Receipt](receipt.md)')
    File.write(File.join(@source, 'references', 'receipt.md'), 'Receipt format.')
    skill(body: '[Guide](references/guide.md)')
    installed = File.join(@root, 'installed', 'review')
    FileUtils.mkdir_p(File.dirname(installed))
    File.symlink(@source, installed)
    report, success = validate(File.dirname(installed))
    assert success
    assert_equal 2, report['links']
    File.unlink(File.join(@source, 'references', 'receipt.md'))
    _, success = validate(File.dirname(installed))
    refute success
  end

  def test_checks_copied_install_independently
    skill(body: '[Guide](references/guide.md)')
    FileUtils.mkdir_p(File.join(@source, 'references'))
    File.write(File.join(@source, 'references', 'guide.md'), 'A guide.')
    installed = File.join(@root, 'copy')
    FileUtils.cp_r(@source, installed)
    File.unlink(File.join(installed, 'references', 'guide.md'))
    _, source_success = validate
    _, copy_success = validate(installed)
    assert source_success
    refute copy_success
  end

  def test_ignores_external_links_and_fenced_examples
    skill(body: "[Docs](https://example.test/docs)\n[Section](#section)\n```md\n[Example](missing.md)\n```\n")
    report, success = validate
    assert success
    assert_equal 0, report['links']
  end

  def test_checks_raw_home_aliases
    skill(body: '`/Users/missing-skill-fixture/skills/absent/SKILL.md`')
    _, success = validate
    refute success
  end

  def test_checks_resources_between_separate_fences
    skill(body: "```sh\necho first\n```\n[Required guide](missing.md)\n~~~sh\necho second\n~~~\n")
    report, success = validate
    refute success
    assert_equal 1, report['links']
    assert report['errors'].any? { |error| error.include?('missing local resource missing.md') }
  end

  def test_ignores_markdown_examples_inside_inline_code
    skill(body: 'Write this pointer in the product README: `[Package](./src/package.md)`.')
    report, success = validate
    assert success
    assert_equal 0, report['links']
  end

  def test_reference_cycles_terminate
    skill(body: '[Reference](reference.md)')
    File.write(File.join(@source, 'reference.md'), '[Entrypoint](SKILL.md)')
    report, success = validate
    assert success
    assert_equal 2, report['resources']
  end

  def test_accepts_folded_descriptions_and_space_in_link
    File.write(File.join(@source, 'a guide.md'), 'A guide.')
    skill(description: ">\n  Review a change\n  with evidence.", body: '[Guide](<a guide.md>)')
    _, success = validate
    assert success
  end
end
