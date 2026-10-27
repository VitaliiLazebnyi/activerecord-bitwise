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

desc 'Run the Sorbet type checker (gem-shipped RBIs are skipped: they are not part of this gem)'
task :typecheck do
  ENV['SRB_SKIP_GEM_RBIS'] = '1'
  sh 'bundle exec srb tc'
end

desc 'Fail unless every public API object is documented'
task :yard do
  output = IO.popen(%w[bundle exec yard stats --list-undoc], err: %i[child out], &:read)
  puts output
  abort 'YARD: undocumented API objects found' unless output.include?(FULLY_DOCUMENTED)
end

desc 'Fail on any code smell (see .reek.yml)'
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

desc 'Run mutation testing (see .mutant.yml)'
task :mutant do
  sh 'bundle exec mutant run'
end

task default: %i[spec rubocop typecheck yard reek flay audit]
