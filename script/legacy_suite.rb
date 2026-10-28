#!/usr/bin/env ruby
# typed: false
# frozen_string_literal: true

# Runs the ORIGINAL spec files of this gem (as they were on `main` before the test and
# refactoring pass) against the current `lib/`, to prove that behavior did not change.
# Every example of the original suite must pass; there is no list of tolerated failures. The only
# edits made to the original files are the corrected 3-byte column capacity and the SimpleCov changes
# described below.

require 'fileutils'
require 'json'
require 'open3'

# The last commit of `main` before the pass; its spec directory is the original suite.
ORIGINAL_COMMIT = '7f2f61bd8b9e7ef0f6f176c48acbf471ea6dcf97'
# How many examples that suite has; fewer would mean part of it silently stopped running.
ORIGINAL_EXAMPLES = 149

root = File.expand_path('..', __dir__)
work = File.join(root, 'tmp', 'legacy')
FileUtils.rm_rf(work)
FileUtils.mkdir_p(work)

archive, status = Open3.capture2('git', 'archive', ORIGINAL_COMMIT, 'spec', chdir: root, binmode: true)
abort "git archive #{ORIGINAL_COMMIT} failed (is the full history fetched?)" unless status.success?
_, status = Open3.capture2('tar', '-x', '-C', work, stdin_data: archive, binmode: true)
abort 'tar failed' unless status.success?

# The one deliberate difference: the original suite pins the bug fixed in this release, that a 3-byte
# column (MySQL MEDIUMINT, which holds 23 signed bits) was validated as if it held 31. Its limit-3
# assertions are updated to the correct capacity (position 22 fits, 23 does not); nothing else changes.
CORRECTED_LIMIT_THREE = {
  "# Position 30 -> valid\n        TestUser.bitwise_definitions[:roles][:validated] = false\n        " \
  'TestUser.bitwise_definitions[:roles][:mapping] = { a: 30 }' =>
    "# Position 22 -> valid\n        TestUser.bitwise_definitions[:roles][:validated] = false\n        " \
    'TestUser.bitwise_definitions[:roles][:mapping] = { a: 22 }',
  "# Position 31 -> fails (max 31 flags)\n        TestUser.bitwise_definitions[:roles][:validated] = false\n        " \
  'TestUser.bitwise_definitions[:roles][:mapping] = { a: 31 }' =>
    "# Position 23 -> fails (max 23)\n        TestUser.bitwise_definitions[:roles][:validated] = false\n        " \
    'TestUser.bitwise_definitions[:roles][:mapping] = { a: 23 }'
}.freeze
original_spec = File.join(work, 'spec', 'activerecord_bitwise_spec.rb')
text = File.read(original_spec)
CORRECTED_LIMIT_THREE.each do |before, after|
  abort "the original suite no longer contains the limit-3 assertion:\n#{before}" unless text.include?(before)

  text = text.sub(before, after)
end
File.write(original_spec, text)

# The second deliberate difference concerns the original spec_helper's SimpleCov block, which targets the
# current SimpleCov differently from this release: it calls the renamed `add_filter` (deprecated, and it
# prints a DEPRECATION notice on every run) and enforces a 100% coverage floor on the files it loads. That
# floor belongs to the old single-file layout; coverage is enforced by this release's own suite, so here
# the floor is dropped and only the API rename is applied. The examples themselves are untouched.
SIMPLECOV_ADAPTATIONS = {
  'add_filter' => 'skip',
  'minimum_coverage line: 100, branch: 100' => 'minimum_coverage line: 0, branch: 0',
  'minimum_coverage line: 99, branch: 99' => 'minimum_coverage line: 0, branch: 0'
}.freeze
original_helper = File.join(work, 'spec', 'spec_helper.rb')
helper = File.read(original_helper)
SIMPLECOV_ADAPTATIONS.each do |before, after|
  abort "the original spec_helper no longer contains: #{before}" unless helper.include?(before)

  helper = helper.gsub(before, after)
end
File.write(original_helper, helper)
# One original example looks for the Tapioca compiler relative to the spec directory.
FileUtils.mkdir_p(File.join(work, 'lib'))
FileUtils.cp_r(File.join(root, 'lib', 'tapioca'), File.join(work, 'lib'))

result = File.join(work, 'result.json')
ENV['BUNDLE_GEMFILE'] = File.join(root, 'Gemfile')
# The per-example JSON result is judged, not the exit code.
system('bundle', 'exec', 'rspec', '--options', File::NULL, '-I', File.join(root, 'lib'), '-I', 'spec',
       '-r', 'spec_helper', '--format', 'json', '--out', result, *Dir.glob('spec/*_spec.rb', base: work),
       chdir: work, out: File::NULL)

report = JSON.parse(File.read(result))
failed = report.fetch('examples').filter_map do |example|
  example.fetch('full_description') if example.fetch('status') == 'failed'
end
puts "Original suite: #{report.dig('summary', 'example_count')} examples, #{failed.size} failing"
failed.each { |name| warn "FAILURE: #{name}" }
errors = Integer(report.dig('summary', 'errors_outside_of_examples_count') || 0)
warn "#{errors} error(s) outside of examples (the suite did not load)" if errors.positive?
exit(failed.empty? && errors.zero? && report.dig('summary', 'example_count') == ORIGINAL_EXAMPLES ? 0 : 1)
