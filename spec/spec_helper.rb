# typed: false
# frozen_string_literal: true

# Must come first: it has to see warnings emitted while lib/ and spec/ are loaded.
require_relative 'support/warning_guard'

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
  # SimpleCov renamed add_filter to skip and warns about the old name on newer releases.
  [%r{/spec/}, %r{/vendor/}].each do |ignored|
    SimpleCov.respond_to?(:skip) ? SimpleCov.skip(ignored) : SimpleCov.add_filter(ignored)
  end

  self.formatters = SimpleCov::Formatter::MultiFormatter.new([
                                                               SimpleCov::Formatter::HTMLFormatter,
                                                               SimpleCov::Formatter::AIFormatter
                                                             ])
end

require 'active_record'
require 'fileutils'
require 'securerandom'
require 'sorbet-runtime'

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

  # A busy timeout lets the concurrency examples queue on SQLite's single writer lock.
  ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: db_file, timeout: 10_000)

  parent_pid = Process.pid
  at_exit do
    # Forked workers (mutant) inherit this hook; only the owning process may delete the file.
    FileUtils.rm_f(db_file) if Process.pid == parent_pid
  end

  # Mutant runs mutations in parallel forked workers that all inherit the connection
  # opened above. Give every worker its own copy of the freshly built database so
  # concurrent suites never contend for one SQLite file.
  RSpec.configure do |config|
    worker_file = nil

    config.before(:suite) do
      next if Process.pid == parent_pid

      worker_file = File.join(db_dir, "test-#{Process.pid}.sqlite3")
      FileUtils.cp(db_file, worker_file)
      ActiveRecord::Base.establish_connection(adapter: 'sqlite3', database: worker_file, timeout: 10_000)
    end

    config.after(:suite) { FileUtils.rm_f(worker_file) if worker_file }
  end
end

require_relative 'support/schema'

# Flush the WAL into the main database file so per-worker copies (see above) are complete.
ActiveRecord::Base.connection.execute('PRAGMA wal_checkpoint(TRUNCATE)') unless database_url

require 'activerecord-bitwise'

Dir[File.join(__dir__, 'support', '**', '*.rb')].each { |support_file| require support_file }

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

  # Mutation testing maps examples to the code they verify by the constant a spec describes.
  # Behavior specified through the public model API (macro, flags, scopes, atomic updates,
  # dirty tracking, ...) exercises many internal modules, so those examples are offered to
  # every subject of the gem; the validator keeps its own, narrower mapping.
  model_level_specs = %r{
    /spec/(
      active_record/bitwise/(model|instance_methods|relation_extension|where_chain_extension)|
      features
    )/
  }x
  config.define_derived_metadata(file_path: model_level_specs) do |metadata|
    metadata[:mutant_expression] = 'ActiveRecord::Bitwise*'
  end

  config.include DatabaseHelpers
  config.include ModelFactory
  config.include RawMarker
  config.include ErrorCapture
  config.include QuietWarnings
  config.include SqlCapture
  config.include RowLockSpy
  config.include ConcurrentRunner

  # Every example starts from empty tables. Rows are deleted (not rolled back) because
  # the concurrency examples need data that is committed and visible to other threads.
  config.before { DatabaseHelpers.truncate_all }

  # Ruby warnings from lib/ or spec/ are failures, never noise.
  config.before(:suite) do
    load_time_warnings = WarningGuard.drain
    raise "Ruby warnings while loading:\n#{load_time_warnings.join}" unless load_time_warnings.empty?
  end

  config.after do
    warnings = WarningGuard.drain
    raise "Ruby warnings emitted by this example:\n#{warnings.join}" unless warnings.empty?
  end

  # Pending and skipped examples hide missing behavior: the suite must not contain any.
  config.after(:suite) do
    unfinished = RSpec.world.all_examples.select do |example|
      example.execution_result.status == :pending || example.skipped? || example.pending?
    end
    unless unfinished.empty?
      raise "Pending or skipped examples are not allowed:\n#{unfinished.map(&:full_description).join("\n")}"
    end
  end
end
