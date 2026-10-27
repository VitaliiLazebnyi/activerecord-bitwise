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

# Mutation runs execute the suite thousands of times against deliberately broken
# code; the coverage gate is meaningless (and noisy) there.
SimpleCov.start do
  next if defined?(Mutant)

  enable_coverage :branch
  # 100% line+branch is enforced on the canonical SQLite run. Alternate adapters
  # (DATABASE_URL set) get a 99% floor instead of a full drop: they cannot reach
  # adapter-specific branches (e.g. PostgreSQL widens limit: 1 columns to
  # smallint, making the tinyint limit branch unreachable), but a 99% gate still
  # fails the run if real coverage regresses.
  if ENV['DATABASE_URL']
    minimum_coverage line: 99, branch: 99
  else
    minimum_coverage line: 100, branch: 100
  end
  add_filter '/spec/'
  add_filter '/vendor/'

  self.formatters = SimpleCov::Formatter::MultiFormatter.new([
                                                               SimpleCov::Formatter::HTMLFormatter,
                                                               SimpleCov::Formatter::AIFormatter
                                                             ])
end

require 'sorbet-runtime'

require 'fileutils'
require 'active_record'

# By default the suite runs on a shared file-based SQLite database (file-based to
# support multi-threaded test isolation). Set DATABASE_URL (e.g. to a PostgreSQL
# server, as CI does) to exercise the gem against a production-grade adapter where
# row locking (`FOR UPDATE`) is real rather than a SQLite no-op.
database_url = ENV.fetch('DATABASE_URL', nil)
if database_url
  ActiveRecord::Base.establish_connection(database_url)
else
  require 'sqlite3'

  db_dir = File.expand_path('../tmp', __dir__)
  FileUtils.mkdir_p(db_dir)
  db_file = File.join(db_dir, 'test.sqlite3')

  ActiveRecord::Base.establish_connection(
    adapter: 'sqlite3',
    database: db_file
  )

  at_exit do
    FileUtils.rm_f(db_file)
  end

  # Mutant runs mutations in parallel forked workers that all inherit the connection
  # opened above. Give every worker its own copy of the freshly built database so
  # concurrent suites never contend for one SQLite file.
  parent_pid = Process.pid
  RSpec.configure do |config|
    worker_file = nil

    config.before(:suite) do
      next if Process.pid == parent_pid

      worker_file = File.join(db_dir, "test-#{Process.pid}.sqlite3")
      FileUtils.cp(db_file, worker_file)
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: worker_file)
    end

    config.after(:suite) { FileUtils.rm_f(worker_file) if worker_file }
  end
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

  create_table :singular_models, force: true do |t|
    t.integer :status, default: 0, null: false
    t.integer :fish, default: 0, null: false
    t.string :name
  end
end

# Flush the WAL into the main database file so per-worker copies (see above) are complete.
ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)') unless database_url

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
