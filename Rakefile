# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'bundler/gem_tasks'
require 'open3'
require 'rspec/core/rake_task'
require 'tmpdir'

# Every gate CI enforces is a task of its own; `rake` runs the ones that need neither the network nor a
# database server, and script/check runs all of them (see CONTRIBUTING.md).

# Ruby's verbose warnings (RUBYOPT=-w, set by CI and script/check) stay on for everything this repository runs,
# except for the third-party tools whose own code warns under -w, which cannot be fixed here: RuboCop (through
# rubocop-md's kramdown) and YARD ("character class has duplicated range" in their regular expressions, and a
# circular require in YARD),
# bundler-audit (it redefines Thor's say_error) and Tapioca (it redefines exit and abort). They keep the
# deprecation and performance warnings.
THIRD_PARTY_RUBYOPT = 'RUBYOPT=-W:deprecated -W:performance'

# Every Ruby source of the repository that Reek, Flay and Flog check: the library, the scripts, the spec helper and
# support code, and the build files. The example groups themselves (spec/**/*_spec.rb) are not: each example is
# written out in full on purpose (arrange, act, assert), so Flay would report every pair of examples that exercise
# the same API, and Flog scores RSpec's example blocks as methods. RuboCop (RSpec department) and Sorbet check them.
RUBY_SOURCES = %w[
  lib script spec/support spec/spec_helper.rb Rakefile activerecord-bitwise.gemspec Gemfile gemfiles
].freeze
# Flog score above which a method counts as too complex and must be split up (flog's "good" band ends at 20).
FLOG_METHOD_THRESHOLD = 20
# Output of `yard stats` when every public API object is documented.
FULLY_DOCUMENTED = '100.00% documented'
# Methods debride sees no caller for, each with the caller it cannot see: Ruby, Rails and Tapioca call them,
# or the gem calls them through a name it builds at runtime.
DEBRIDE_ALLOWED = {
  _bitwise_atomic_update!: 'called through the generated add_/remove_ methods (Model::GeneratedMethods)',
  _write_attribute: 'ActiveRecord::AttributeMethods::Write override, called by Rails',
  initialize_dup: 'Ruby calls it from #dup',
  _bitwise_flag_assign: 'called through the generated flag= methods (GeneratedMethods::FLAG_ASSIGN)',
  _bitwise_flag_enabled?: 'called through the generated flag? methods (GeneratedMethods::FLAG_QUERY)',
  _bitwise_flag_save: 'called through the generated flag! methods (GeneratedMethods::FLAG_SAVE)',
  _bitwise_read: 'called through the generated column getter (GeneratedMethods::READ)',
  with_any: 'called through the generated with_any_ scopes (Model::Scopes::SCOPES)',
  with_exact: 'called through the generated with_exact_ scopes (Model::Scopes::SCOPES)',
  without: 'called through the generated without_ scopes (Model::Scopes::SCOPES)',
  ConstantType: 'the type member Tapioca reads from every DSL compiler',
  extended: 'Ruby calls it when a class extends ActiveRecord::Bitwise::Model',
  inherited: 'Ruby calls it when a model class is subclassed',
  create_path: 'the spec stand-in for RBI::Tree#create_path, called by the Tapioca compiler under test',
  to_i: 'the spec stand-in bitmask, converted by Integer() in lib/',
  warn: "Ruby's Warning module calls it (spec/support/warning_guard.rb)"
}.freeze

# Runs the tools whose report, not only their exit status, says whether they found anything.
module Report
  # Prints a tool's report and fails unless the tool succeeded and the report says it found nothing.
  # @param command [Array<String>] The tool's command line.
  # @param clean [String] The text the report holds when there is nothing to fix.
  # @param failure [String] The message to abort with otherwise.
  # @return [void]
  def self.require_clean(command, clean, failure)
    output, status = Open3.capture2e(*command)
    puts(output)
    abort(failure) unless status.success? && output.include?(clean)
  end
end

RSpec::Core::RakeTask.new(:spec)

desc 'Run RuboCop with every cop of RuboCop and its plugins (no todo file, no inline directives)'
task :rubocop do
  sh 'env', THIRD_PARTY_RUBYOPT, 'bundle', 'exec', 'rubocop'
end

desc 'Fail on inline suppressions of any linter, scanner, type checker, warning or test'
task :suppressions do
  sh 'script/forbidden_suppressions.sh'
end

desc 'Generate the gem RBIs with Tapioca (the optional :typecheck group), then run the Sorbet type checker'
task :typecheck do
  # Tapioca is in an optional group of the bundle. Under `bundle exec rake` the environment
  # (RUBYOPT=-rbundler/setup) is set up without it, so the nested commands run in an unbundled environment.
  Bundler.with_unbundled_env do
    typecheck = ['env', THIRD_PARTY_RUBYOPT, 'BUNDLE_WITH=typecheck', 'BUNDLE_FROZEN=true', 'bundle']
    sh(*typecheck, 'install', '--quiet')
    sh(*typecheck, 'exec', 'tapioca', 'gem')
  end
  # Tapioca already merges the RBIs that gems ship themselves (e.g. prism, spoom) into the generated ones;
  # srb must not load them a second time.
  sh('env', 'SRB_SKIP_GEM_RBIS=1', 'bundle', 'exec', 'srb', 'tc')
end

desc 'Parse the YARD documentation (warnings are fatal), require 100% coverage and a description everywhere'
task :yard do
  sh 'env', THIRD_PARTY_RUBYOPT, 'bundle', 'exec', 'yardoc', '--fail-on-warning', '--no-output'
  Report.require_clean(
    ['env', THIRD_PARTY_RUBYOPT, 'bundle', 'exec', 'yard', 'stats', '--list-undoc'],
    FULLY_DOCUMENTED,
    'YARD: undocumented API objects found'
  )
  sh 'env', THIRD_PARTY_RUBYOPT, 'bundle', 'exec', 'ruby', 'script/check_docs.rb'
end

desc 'Fail on any code smell (default Reek configuration, no exclusions)'
task :reek do
  sh 'bundle', 'exec', 'reek', *RUBY_SOURCES
end

desc 'Fail on any structural duplication (default Flay mass)'
task :flay do
  Report.require_clean(
    ['bundle', 'exec', 'flay', *RUBY_SOURCES],
    'Total score (lower is better) = 0',
    'Flay: duplicated code found'
  )
end

desc "Fail on any method with a flog score above #{FLOG_METHOD_THRESHOLD}"
task :flog do
  report, status = Open3.capture2e('bundle', 'exec', 'flog', '--all', '--methods-only', *RUBY_SOURCES)
  puts report
  abort 'flog failed' unless status.success?
  scores = report.scan(/^\s*(\d+\.\d+): (\S+)\s+\S+:\d+/)
  complex = scores.filter_map { |score, name| name if Float(score) > FLOG_METHOD_THRESHOLD }
  abort "flog: methods scoring above #{FLOG_METHOD_THRESHOLD}: #{complex.join(', ')}" unless complex.empty?
end

desc 'Fail on any method nothing calls (debride over every Ruby source and spec/; see DEBRIDE_ALLOWED)'
task :debride do
  Dir.mktmpdir('debride') do |dir|
    allowed = File.join(dir, 'allowed.txt')
    File.write(allowed, DEBRIDE_ALLOWED.keys.join("\n"))
    Report.require_clean(
      ['bundle', 'exec', 'debride', '--rails', '--whitelist', allowed, *RUBY_SOURCES, 'spec'],
      'Total suspect LOC: 0',
      'debride: methods without a caller found'
    )
  end
end

desc 'Audit the locked gems against the Ruby Advisory Database'
task :audit do
  sh 'env', THIRD_PARTY_RUBYOPT, 'bundle', 'exec', 'bundler-audit', 'check', '--update'
end

desc 'Fail on outdated dependencies that are not on the documented hold list (needs the network)'
task :outdated do
  ruby 'script/outdated.rb'
end

desc 'Build the gem strictly (warnings are fatal), then install and require it from a clean GEM_HOME'
task :package do
  gemspec = Gem::Specification.load('activerecord-bitwise.gemspec')
  gem_file = "#{gemspec.name}-#{gemspec.version}.gem"
  # Outside the bundle, in an empty HOME: the build is unsigned, as on CI (a signing key in the developer's own
  # ~/.gem is not used; only the release signs), and the smoke test sees only the freshly installed gem and its
  # dependencies.
  Bundler.with_unbundled_env do
    Dir.mktmpdir('activerecord-bitwise-smoke') do |home|
      clean_env = ['env', "HOME=#{home}", "GEM_HOME=#{home}/gems", "GEM_PATH=#{home}/gems"]
      sh(*clean_env, 'gem', 'build', 'activerecord-bitwise.gemspec', '--strict')
      sh(*clean_env, 'gem', 'install', '--no-document', gem_file)
      sh(*clean_env, 'ruby', '-e', 'require "activerecord-bitwise"; puts ActiveRecord::Bitwise::VERSION')
    end
  end
ensure
  FileUtils.rm_f(gem_file) if gem_file
end

desc 'Mutation testing with mutant (see .mutant.yml); MUTANT_SINCE=<revision> limits it to touched subjects'
task :mutant do
  command = %w[bundle exec mutant run]
  command.push('--since', ENV.fetch('MUTANT_SINCE')) if ENV.key?('MUTANT_SINCE')
  sh(*command)
end

desc 'Run the original (pre-refactoring) spec suite against the current lib/'
task :legacy_suite do
  ruby 'script/legacy_suite.rb'
end

task default: %i[spec legacy_suite rubocop suppressions typecheck yard reek flay flog debride audit package]
