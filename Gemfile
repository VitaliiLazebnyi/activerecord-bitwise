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
gem 'pg', '~> 1.7' if ENV.fetch('DATABASE_URL', '').start_with?('postgres')
