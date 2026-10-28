# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

# Flay mass threshold. At the default (16) Flay only reports identical Sorbet `sig`
# declarations of sibling methods; from 24 up it reports every duplicated piece of logic.
FLAY_MASS = 24

# Output of `yard stats` when every public API object is documented.
FULLY_DOCUMENTED = '100.00% documented'

RSpec::Core::RakeTask.new(:spec)

desc 'Run RuboCop'
task :rubocop do
  sh 'bundle exec rubocop'
end

desc 'Fail on inline suppressions of any linter, scanner, type checker, warning or test'
task :suppressions do
  sh 'script/forbidden_suppressions.sh'
end

desc 'Generate the gem RBIs with Tapioca, then run the Sorbet type checker'
task :typecheck do
  sh 'env BUNDLE_GEMFILE=gemfiles/typecheck.gemfile sh -c "bundle install --quiet && bundle exec tapioca gem"'
  sh 'bundle exec srb tc'
end

desc 'Fail unless every public API object is documented'
task :yard do
  output = IO.popen(%w[bundle exec yard stats --list-undoc], err: %i[child out], &:read)
  puts output
  abort 'YARD: undocumented API objects found' unless output.include?(FULLY_DOCUMENTED)
end

desc 'Fail on any code smell (default Reek configuration, no exclusions)'
task :reek do
  sh 'bundle exec reek lib'
end

desc 'Fail on any structural duplication'
task :flay do
  output = IO.popen(['bundle', 'exec', 'flay', '--mass', FLAY_MASS.to_s, 'lib'], &:read)
  puts output
  abort 'Flay: duplicated code found' unless output.start_with?('Total score (lower is better) = 0')
end

desc 'Audit gem dependencies for known vulnerabilities'
task :audit do
  sh 'bundle exec bundler-audit check --update'
end

desc 'Fail on outdated gems that are not on the documented hold list'
task :outdated do
  ruby 'script/outdated.rb'
end

desc 'Run mutation testing (see .mutant.yml)'
task :mutant do
  sh 'bundle exec mutant run'
end

desc 'Run the original (pre-refactoring) spec suite against the current lib/'
task :legacy_suite do
  ruby 'script/legacy_suite.rb'
end

task default: %i[spec legacy_suite rubocop suppressions typecheck yard reek flay audit]
