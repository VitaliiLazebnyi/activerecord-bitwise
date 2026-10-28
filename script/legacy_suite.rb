#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs the ORIGINAL spec files of this gem (as they were on `main` before the test and
# refactoring pass) against the current `lib/`, to prove that behavior did not change.
#
# Every example of the original suite must pass, except the ones listed in
# script/legacy_suite_expected_failures.txt: those assert private implementation details
# that were removed on purpose (each entry says why). The task fails when any other example
# fails, and also when a listed example starts passing (so the list cannot go stale).

require 'fileutils'
require 'json'
require 'open3'

# The last commit of `main` before the pass; its spec directory is the original suite.
ORIGINAL_COMMIT = '7f2f61bd8b9e7ef0f6f176c48acbf471ea6dcf97'

root = File.expand_path('..', __dir__)
work = File.join(root, 'tmp', 'legacy')
FileUtils.rm_rf(work)
FileUtils.mkdir_p(work)

archive, status = Open3.capture2('git', 'archive', ORIGINAL_COMMIT, 'spec', chdir: root, binmode: true)
abort "git archive #{ORIGINAL_COMMIT} failed (is the full history fetched?)" unless status.success?
_, status = Open3.capture2('tar', '-x', '-C', work, stdin_data: archive, binmode: true)
abort 'tar failed' unless status.success?
# One original example looks for the Tapioca compiler relative to the spec directory.
FileUtils.mkdir_p(File.join(work, 'lib'))
FileUtils.cp_r(File.join(root, 'lib', 'tapioca'), File.join(work, 'lib'))

result = File.join(work, 'result.json')
env = { 'BUNDLE_GEMFILE' => File.join(root, 'Gemfile') } # rubocop:disable Style/StringHashKeys -- ENV names are Strings
# The original spec_helper enforces its own coverage floor on the files it loads; the exit code is
# therefore ignored and the per-example JSON result is judged instead.
system(env, 'bundle', 'exec', 'rspec', '--options', File::NULL, '-I', File.join(root, 'lib'), '-I', 'spec',
       '-r', 'spec_helper', '--format', 'json', '--out', result, *Dir.glob('spec/*_spec.rb', base: work),
       chdir: work, out: File::NULL)

report = JSON.parse(File.read(result))
failed = report.fetch('examples').filter_map do |example|
  example.fetch('full_description') if example.fetch('status') == 'failed'
end
expected = File.readlines(File.join(root, 'script', 'legacy_suite_expected_failures.txt'), chomp: true)
               .reject { |line| line.empty? || line.start_with?('#') }

unexpected = failed - expected
stale = expected - failed
puts "Original suite: #{report.dig('summary', 'example_count')} examples, #{failed.size} failing " \
     "(#{expected.size} expected)"
unexpected.each { |name| warn "UNEXPECTED FAILURE: #{name}" }
stale.each { |name| warn "EXPECTED FAILURE NOW PASSES (remove it from the list): #{name}" }
exit(unexpected.empty? && stale.empty? ? 0 : 1)
