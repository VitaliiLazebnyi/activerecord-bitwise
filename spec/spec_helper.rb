# frozen_string_literal: true

require 'simplecov'
require 'simplecov-ai'

SimpleCov::Formatter::AIFormatter.configure do |config|
  config.report_path = 'coverage/ai_report.md'
  config.max_file_size_kb = 50
  config.max_snippet_lines = 5
  config.output_to_console = false
  config.granularity = :fine
  config.include_bypasses = true
end

SimpleCov.start do
  enable_coverage :branch
  minimum_coverage line: 100, branch: 100
  add_filter '/spec/'
  add_filter '/vendor/'

  self.formatters = SimpleCov::Formatter::MultiFormatter.new([
                                                               SimpleCov::Formatter::HTMLFormatter,
                                                               SimpleCov::Formatter::AIFormatter
                                                             ])
end

require 'sorbet-runtime'

require 'fileutils'
require 'sqlite3'
require 'active_record'

# Establish a shared file-based SQLite database to support multi-threaded test isolation
db_dir = File.expand_path('../tmp', __dir__)
FileUtils.mkdir_p(db_dir)
db_file = File.join(db_dir, 'test.sqlite3')

ActiveRecord::Base.establish_connection(
  adapter: 'sqlite3',
  database: db_file
)

at_exit do
  FileUtils.rm_f(db_file) if defined?(db_file) && File.exist?(db_file)
end

# Set up testing database schema
ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :type
    t.integer :roles, default: 0, null: true
    t.integer :permissions, default: 0, null: false
    t.integer :legacy_roles, default: 0, null: false
    t.integer :custom_limits, limit: 1, default: 0, null: false
  end

  create_table :over_shifted_models, force: true do |t|
    t.integer :custom_limits, limit: 1, default: 0, null: false
  end

  create_table :collision_models, force: true do |t|
    t.integer :states, default: 0, null: false
  end

  create_table :saas_users, force: true do |t|
    t.string :name, null: false
    t.integer :roles, default: 0, null: false
    t.integer :features, default: 0, null: false
  end

  create_table :etl_records, force: true do |t|
    t.string :external_id, null: false
    t.integer :legacy_flags, default: 0, null: false
  end
end

require 'activerecord-bitwise'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
