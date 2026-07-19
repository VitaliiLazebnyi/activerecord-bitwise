# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in activerecord-bitwise.gemspec
gemspec

# Allow CI to pin a specific ActiveRecord release, e.g. AR_VERSION="~> 7.1.0"
gem 'activerecord', ENV['AR_VERSION'] if ENV['AR_VERSION']

# PostgreSQL adapter for running the suite against a real server (see spec_helper)
gem 'pg', '~> 1.6' if ENV.fetch('DATABASE_URL', '').start_with?('postgres') # matches postgres:// and postgresql://
