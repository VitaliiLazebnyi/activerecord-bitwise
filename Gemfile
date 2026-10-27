# frozen_string_literal: true

source 'https://rubygems.org'

# Runtime and test dependencies come from the gemspec.
gemspec

# Allow CI to pin a specific ActiveRecord release, e.g. AR_VERSION="~> 7.1.0".
gem 'activerecord', ENV.fetch('AR_VERSION') if ENV.key?('AR_VERSION')

# Alternate database adapters for running the suite against a real server (see spec_helper).
# MySQL adapter, only installed when DATABASE_URL targets MySQL.
gem 'mysql2', '~> 0.5' if ENV.fetch('DATABASE_URL', '').start_with?('mysql2')
# PostgreSQL adapter, only installed when DATABASE_URL targets PostgreSQL (postgres:// and postgresql://).
gem 'pg', '~> 1.6' if ENV.fetch('DATABASE_URL', '').start_with?('postgres')

# Quality tooling (linting, typing, documentation, mutation testing, dependency audit).
# These gems require Ruby >= 3.3, so the Ruby 3.2 CI job only runs the test suite.
if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new('3.3')
  group :quality do
    # Fails the build on dependencies with known vulnerabilities.
    gem 'bundler-audit', '~> 0.9'
    # Structural duplication detection.
    gem 'flay', '~> 2.14'
    # Mutation testing (free for open source via `usage: opensource`).
    gem 'mutant-rspec', '~> 0.17'
    # Code smell detection.
    gem 'reek', '~> 6.6'
    # Rake tasks (release, etc.).
    gem 'rake', '~> 13.4'
    # Linter and its plugins.
    gem 'rubocop', '~> 1.92'
    gem 'rubocop-md', '~> 2.0'
    gem 'rubocop-performance', '~> 1.27'
    gem 'rubocop-rake', '~> 0.7'
    gem 'rubocop-rspec', '~> 3.10'
    gem 'rubocop-sorbet', '~> 0.17'
    gem 'rubocop-thread_safety', '~> 0.8'
    # Static type checker.
    gem 'sorbet', '~> 0.6'
    # API documentation (must stay 100% documented) and its Sorbet plugin.
    gem 'yard', '~> 0.9'
    gem 'yard-sorbet', '~> 0.9'
  end
end
