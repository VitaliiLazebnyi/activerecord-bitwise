# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec)

desc 'Run RuboCop'
task :rubocop do
  sh 'bundle exec rubocop'
end

desc 'Run the Sorbet type checker'
task :typecheck do
  sh 'bundle exec srb tc'
end

desc 'Audit gem dependencies for known vulnerabilities'
task :audit do
  sh 'bundle exec bundler-audit check --update'
end

desc 'Run mutation testing (see .mutant.yml)'
task :mutant do
  sh 'bundle exec mutant run'
end

task default: %i[spec rubocop typecheck]
