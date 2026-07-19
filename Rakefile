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

task default: %i[spec rubocop typecheck]
