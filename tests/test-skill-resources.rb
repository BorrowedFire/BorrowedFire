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

  def validate(path = @source, copy: false)
    args = ['ruby', VALIDATOR, '--json']
    args << '--copy-layout' if copy
    output, error, status = Open3.capture3(*args, path)
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
    skill(body: "[Docs](https://example.test/docs)\n[Section](#section)\n[Product analytics](/features/analytics)\n```md\n[Example](missing.md)\n```\n")
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

  def test_used_reference_styles_reject_missing_resources
    ['[Guide][resource]', '[resource][]', '[resource]'].each do |usage|
      skill(body: "#{usage}\n\n[resource]: missing.md\n")
      report, success = validate
      refute success
      assert_equal 1, report['links']
    end
  end

  def test_empty_inline_labels_and_image_alt_text_still_check_resources
    ['[](missing.md)', '![](diagram.svg)'].each do |usage|
      skill(body: usage)
      report, success = validate
      refute success
      assert_equal 1, report['links']
    end
  end

  def test_reference_labels_normalize_case_and_whitespace
    File.write(File.join(@source, 'a guide.md'), 'A guide.')
    skill(body: "[Guide][The   Guide]\n\n[the guide]:\n  <a guide.md> \"Optional title\"\n")
    report, success = validate
    assert success
    assert_equal 1, report['links']
  end

  def test_unused_and_example_definitions_do_not_activate_resources
    skill(body: "[Guide](https://example.test)\n`[Unused]`\n\\[Escaped]\n```md\n[Fenced]\n```\n\n[Guide]: missing.md\n[Unused]: missing.md\n[Escaped]: missing.md\n[Fenced]: missing.md\n")
    report, success = validate
    assert success
    assert_equal 0, report['links']
  end

  def test_reference_links_follow_installed_transitive_resources
    skill(body: "[Guide][guide]\n\n[guide]: guide.md\n")
    File.write(File.join(@source, 'guide.md'), "[Receipt][]\n\n[receipt]: receipt.md\n")
    File.write(File.join(@source, 'receipt.md'), 'Receipt.')
    installed = File.join(@root, 'installed')
    File.symlink(@source, installed)
    report, success = validate(installed)
    assert success
    assert_equal 2, report['links']
    File.unlink(File.join(@source, 'receipt.md'))
    _, success = validate(installed)
    refute success
  end

  def test_multiline_inline_destinations_and_titles_are_checked
    ["[Guide](\nmissing.md\n)", "![Guide](\n<missing guide.svg>\n\"Title\"\n)",
     "[Guide](\nmissing.md\n'Optional title'\n)",
     "[Guide](missing.md \"Wrapped\ntitle\")", "[Guide](missing.md 'Wrapped\ntitle')",
     "[Guide](missing.md (Wrapped\ntitle))"].each do |usage|
      skill(body: usage)
      report, success = validate
      refute success
      assert_equal 1, report['links']
    end
    File.write(File.join(@source, 'guide.md'), 'Guide.')
    skill(body: "[Guide](\n  guide.md\n  \"Title\"\n)\n")
    report, success = validate(copy: true)
    assert success
    assert_equal 1, report['links']
  end

  def test_copy_layout_rejects_symlinked_skill_roots
    skill(body: 'A self-contained skill.')
    linked = File.join(@root, 'linked')
    File.symlink(@source, linked)
    _, source_success = validate(linked)
    report, copy_success = validate(linked, copy: true)
    assert source_success
    refute copy_success
    assert report['errors'].any? { |error| error.include?('copied skill roots must be directories, not symlinks') }
  end

  def test_copy_layout_rejects_existing_resource_outside_skill_directories
    File.write(File.join(@root, 'README.md'), 'Repository resource.')
    skill(body: '[Guide](../../README.md)')
    _, source_success = validate
    report, copy_success = validate(copy: true)
    assert source_success
    refute copy_success
    assert report['errors'].any? { |error| error.include?('missing local resource') }
  end

  def test_copy_layout_excludes_loose_files_beside_skills
    File.write(File.join(@root, 'source', 'SHARED.md'), 'Loose resource.')
    skill(body: '[Shared](../SHARED.md)')
    _, source_success = validate(File.dirname(@source))
    _, copy_success = validate(File.dirname(@source), copy: true)
    assert source_success
    refute copy_success
  end

  def test_copy_layout_keeps_packaged_cross_skill_resources
    other = File.join(@root, 'source', 'other')
    FileUtils.mkdir_p(other)
    File.write(File.join(other, 'SKILL.md'), "---\nname: other\ndescription: Read another skill.\n---\n")
    File.write(File.join(other, 'guide.md'), 'Packaged guide.')
    skill(body: '[Other guide](../other/guide.md)')
    report, success = validate(File.dirname(@source), copy: true)
    assert success
    assert_equal 2, report['skills']
    assert_equal 1, report['links']
  end

  def test_copy_layout_checks_asset_symlink_boundaries
    File.write(File.join(@root, 'outside.svg'), '<svg/>')
    File.symlink(File.join(@root, 'outside.svg'), File.join(@source, 'diagram.svg'))
    skill(body: '![Diagram](diagram.svg)')
    _, source_success = validate
    report, copy_success = validate(copy: true)
    assert source_success
    refute copy_success
    assert report['errors'].any? { |error| error.include?('escapes the copied skill layout') }
  end

  def test_copy_layout_keeps_internal_symlinks_but_rejects_external_entrypoints
    File.write(File.join(@source, 'guide.md'), 'Guide.')
    File.symlink('guide.md', File.join(@source, 'alias.md'))
    skill(body: '[Guide](alias.md)')
    _, success = validate(copy: true)
    assert success
    FileUtils.mv(File.join(@source, 'SKILL.md'), File.join(@root, 'outside.md'))
    File.symlink(File.join(@root, 'outside.md'), File.join(@source, 'SKILL.md'))
    report, success = validate(copy: true)
    refute success
    assert report['errors'].any? { |error| error.include?('escapes the copied skill layout') }
  end

  def test_installer_preflight_checks_the_copied_resource_layout
    checkout = File.join(@root, 'checkout')
    FileUtils.mkdir_p(checkout)
    source = File.expand_path('..', __dir__)
    Dir.children(source).reject { |name| name == '.git' }.each do |name|
      FileUtils.cp_r(File.join(source, name), File.join(checkout, name))
    end
    lint = File.join(checkout, 'tools', 'skill-lint.sh')
    _, _, before = Open3.capture3('bash', lint)
    assert before.success?, 'The intact installer preflight must pass.'
    File.open(File.join(checkout, 'skills', 'changelog', 'SKILL.md'), 'a') do |file|
      file.puts "\n[Repository guide](../../README.md)"
    end
    output, errors, after = Open3.capture3('bash', lint)
    refute after.success?
    assert_includes output + errors, 'missing local resource ../../README.md'
  end

  def test_balanced_links_resolve_complete_destinations
    cases = [
      ['[Guide [advanced]](guide.md)', ['guide.md']],
      ['[[Guide](guide.md)]', ['guide.md']],
      ['[See [Guide](guide.md)]', ['guide.md']],
      ["[See [guide]]\n\n[guide]: guide.md", ['guide.md']],
      ['[Guide \\[advanced\\]](guide.md)', ['guide.md']],
      ["[Guide\nadvanced](guide.md)", ['guide.md']],
      ['[Guide](guide(one(two)).md)', ['guide(one(two)).md']],
      ['[Guide](guide\\(one\\).md)', ['guide(one).md']],
      ['[Guide](<a guide(one).md>)', ['a guide(one).md']],
      ['[![Alt](image.svg)](guide.md)', ['guide.md', 'image.svg']],
      ['[Outer [Guide](guide.md)](inactive.md)', ['guide.md']],
      ['![Alt [Guide](inactive.md)](image.svg)', ['image.svg']],
      ["[Guide [advanced]][resource]\n\n[resource]: guide(one(two)).md", ['guide(one(two)).md']],
      ["[ReSoUrCe][]\n\n[resource]: guide.md?raw=1#usage", ['guide.md']],
      ["[resource]\n\n[resource]: guide.md", ['guide.md']],
      ["[resource]\n\n[resource]: guide.md \"Wrapped\n[text](unused.md)\"", ['guide.md']],
      ['[Guide](guide.md "Title with \\"quotes\\" and [text](unused.md)")', ['guide.md']]
    ]
    cases.each do |body, paths|
      skill(body: body)
      missing, success = validate(copy: true)
      refute success, body
      assert_equal paths.length, missing['links'], body
      paths.each { |path| File.write(File.join(@source, path), 'Resource.') }
      present, success = validate(copy: true)
      assert success, "#{body}: #{present['errors']}"
      assert_equal paths.length, present['links'], body
      paths.each { |path| File.unlink(File.join(@source, path)) }
    end
  end

  def test_uri_paths_drop_suffixes_before_decoding_once
    {
      'guide.md?raw=1#usage' => 'guide.md',
      'guide%23part.md#usage' => 'guide#part.md',
      'a%3Fb.md?raw=1' => 'a?b.md',
      'a+b.md' => 'a+b.md',
      '%252e.md' => '%2e.md'
    }.each do |url, path|
      skill(body: "[Guide](#{url})")
      report, success = validate(copy: true)
      refute success
      assert_equal 1, report['links']
      File.write(File.join(@source, path), 'Resource.')
      report, success = validate(copy: true)
      assert success, report['errors'].inspect
      assert_equal 1, report['links']
      File.unlink(File.join(@source, path))
    end
    skill(body: '[Section](#usage) [Query](?raw=1)')
    report, success = validate(copy: true)
    assert success
    assert_equal 0, report['links']
  end

  def test_encoded_paths_keep_copy_boundaries_and_reject_nul
    File.write(File.join(@root, 'outside.md'), 'Outside.')
    ['%2e%2e/%2e%2e/outside.md', 'guide%00.md'].each do |url|
      skill(body: "[Guide](#{url})")
      report, success = validate(copy: true)
      refute success
      refute_empty report['errors']
    end
  end

  def test_inner_reference_takes_precedence_over_outer_link
    File.write(File.join(@source, 'advanced.md'), 'Guide.')
    skill(body: "[Guide [advanced]](inactive.md)\n\n[advanced]: advanced.md\n")
    report, success = validate
    assert success
    assert_equal 1, report['links']
  end

  def test_malformed_balancing_does_not_emit_truncated_destinations
    ['[Guide](guide(one.md)', '[Guide [advanced(guide.md)',
     '[Guide](guide.md "unclosed title)', '[Guide](<guide.md)'].each do |body|
      skill(body: body)
      report, success = validate
      assert success, report['errors'].inspect
      assert_equal 0, report['links'], body
    end
  end

  def test_exact_backtick_spans_preserve_link_boundaries
    skill(body: "``code ` [Example](missing.md)``\n[label]`code`(missing.md)\n")
    report, success = validate
    assert success
    assert_equal 0, report['links']
    skill(body: "``code ` example`` [Guide](missing.md)")
    report, success = validate
    refute success
    assert_equal 1, report['links']
  end

  def test_unmatched_outer_label_keeps_a_valid_inner_link
    skill(body: '[Unmatched [Guide](missing.md)')
    report, success = validate
    refute success
    assert_equal 1, report['links']
  end

  def test_reference_label_requires_adjacency
    File.write(File.join(@source, 'one.md'), 'First guide.')
    File.write(File.join(@source, 'two.md'), 'Second guide.')
    skill(body: "[one] [two]\n\n[one]: one.md\n[two]: two.md\n")
    report, success = validate
    assert success
    assert_equal 2, report['links']
    File.unlink(File.join(@source, 'one.md'))
    report, success = validate
    refute success
    assert_equal 2, report['links']
    assert report['errors'].any? { |error| error.include?('missing local resource one.md') }
  end
end
