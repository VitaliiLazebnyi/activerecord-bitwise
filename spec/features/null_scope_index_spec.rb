# typed: false
# frozen_string_literal: true

# The scopes that read a NULL column as "no flags" compare with `= 0 OR IS NULL` rather than wrapping the
# column in COALESCE, so an index on the column stays usable. This is only observable on PostgreSQL.
if DatabaseHelpers.postgres_adapter?
  RSpec.describe 'NULL-aware scopes on PostgreSQL' do
    include_context 'with a user model'

    let(:plan) { ActiveRecord::Base.connection.select_values("EXPLAIN #{model.with_exact_roles.to_sql}").join("\n") }

    around do |example|
      ActiveRecord::Base.connection.execute('SET enable_seqscan = off')
      example.run
    ensure
      ActiveRecord::Base.connection.execute('RESET enable_seqscan')
    end

    after { RSpec.configuration.reporter.message("EXPLAIN for with_exact_roles:\n#{plan}") }

    it 'uses the index on the column for the "no flags" comparison' do
      expect(plan).to match(/Index|Bitmap/)
    end

    it 'does not fall back to a sequential scan' do
      expect(plan).not_to include('Seq Scan')
    end
  end
end
