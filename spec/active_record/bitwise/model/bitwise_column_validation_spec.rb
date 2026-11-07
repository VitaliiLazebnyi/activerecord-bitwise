# typed: true
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

RSpec.describe(ActiveRecord::Bitwise::Model, '#bitwise') do
  # Validation of the column against the mapping happens lazily, on first instantiation.
  # A signed column of N bytes holds N * 8 - 1 flags (positions 0..N * 8 - 2): the sign bit is
  # never used. A column without a byte limit is a 4-byte INTEGER.
  let(:define) do
    lambda do |column, position|
      build_model('capacity_records') { bitwise column, { flag: position } }
    end
  end

  # Runs +check+ for the column of every byte size, each in a failure group named after the column, with the
  # number of flags the column holds and the byte size the database actually reports for it (PostgreSQL widens
  # 1 byte to 2 and 3 to 4).
  let(:each_column) do
    lambda do |columns = %i[tiny small medium regular big], &check|
      columns.each do |column|
        limit = build_model('capacity_records').columns_hash.fetch(column.to_s).limit || 4
        aggregate_failures(column.inspect) { check.call(column, (limit * 8) - 1, limit) }
      end
    end
  end

  it 'accepts the highest bit position that fits a column of every byte size', :aggregate_failures do
    each_column.call do |column, flags|
      expect { define.call(column, flags - 1).new }
        .not_to(raise_error)
    end
  end

  # An 8-byte column fits every position the mapping allows, so there is nothing to reject.
  it 'rejects the first bit position that does not fit a column of every smaller byte size', :aggregate_failures do
    each_column.call(%i[tiny small medium regular]) do |column, flags, limit|
      message = "Bitwise column #{column} has limit of #{limit} bytes " \
        "(max #{flags} flags), but mapping requires bit shift position #{flags}."
      expect(&-> { define.call(column, flags).new }).to(raise_error(ArgumentError, message))
    end
  end

  it 'stores the highest flag of a column of every byte size exactly', :aggregate_failures do
    each_column.call do |column, flags|
      record = define.call(column, flags - 1).create!(column => [:flag])

      expect(raw_value(record, column)).to(eq(1 << (flags - 1)))
    end
  end

  # A 5-byte column is not a size any database offers natively (MySQL and PostgreSQL widen it to
  # BIGINT); where it is kept (SQLite) the gem assumes the 4-byte capacity of a plain INTEGER. The examples run
  # on every database, so they expect what the connected one does with the column.
  odd_bytes = DatabaseHelpers.column_limit('capacity_records', 'odd')
  context "with an unusual byte size (reported as #{odd_bytes} bytes)" do
    let(:kept)      { DatabaseHelpers.column_limit('capacity_records', 'odd') == 5 }
    let(:odd_flags) { kept ? 31 : 63                                               }
    # The first position past the capacity: past the 31 flags of a kept 5-byte column, or, for a BIGINT, which
    # holds every position the mapping accepts (0..62), not a bit position at all.
    let(:first_misfit) do
      if kept
        [
          ArgumentError,
          'Bitwise column odd has limit of 5 bytes (max 31 flags), but mapping requires bit shift position 31.'
        ]
      else
        [ActiveRecord::Bitwise::ConfigurationError, /invalid bit position 63\./]
      end
    end

    it 'is kept at 5 bytes or widened to a BIGINT by the database' do
      expect(DatabaseHelpers.column_limit('capacity_records', 'odd')).to(eq(5).or(eq(8)))
    end

    it 'accepts the highest bit position that fits' do
      expect { define.call(:odd, odd_flags - 1).new }
        .not_to(raise_error)
    end

    it 'rejects the first bit position that does not fit' do
      expect { define.call(:odd, odd_flags).new }
        .to(raise_error(*first_misfit))
    end
  end

  # Not every adapter offers every byte size (PostgreSQL has no 1- or 3-byte integers), so the capacity
  # table is also checked against a wrapper around the real column that reports another limit.
  context 'with a column that reports another byte size' do
    # Reported byte limit -> flags the column holds.
    let(:capacities) { { 1 => 7, 2 => 15, 3 => 23, 4 => 31, 8 => 63, 5 => 31, nil => 31 } }
    let(:model_with_limit) do
      lambda do |reported_limit, position|
        model = define.call(:regular, position)
        real = model.columns_hash
        reported = ColumnWithLimit.new(real.fetch('regular'), reported_limit)
        allow(model).to(receive(:columns_hash).and_return(real.dup.tap { |copy| copy.store('regular', reported) }))
        model
      end
    end

    it 'accepts the highest position that fits each size', :aggregate_failures do
      capacities.each do |limit, flags|
        instantiate = -> { model_with_limit.call(limit, flags - 1).new }
        aggregate_failures("#{limit.inspect} bytes") { expect(&instantiate).not_to(raise_error) }
      end
    end

    # An 8-byte column holds every position the mapping itself accepts, so there is nothing to reject.
    it 'rejects the first position that does not fit each size below 8 bytes', :aggregate_failures do
      capacities.except(8).each do |limit, flags|
        instantiate = -> { model_with_limit.call(limit, flags).new }
        aggregate_failures(limit.inspect) { expect(&instantiate).to(raise_error(ArgumentError, /max #{flags} flags/)) }
      end
    end
  end

  context 'with the default (4-byte) capacity on SQLite' do
    it 'allows 31 flags (positions 0..30)' do
      expect { define.call(:regular, 30).new }
        .not_to(raise_error)
    end
  end

  context 'with a column that is not an integer' do
    it 'raises ArgumentError' do
      expect { define.call(:label, 0).new }
        .to(raise_error(ArgumentError, 'Bitwise column label must be an integer database column'))
    end
  end

  context 'with a column that does not exist' do
    it 'raises ArgumentError' do
      expect { define.call(:nonexistent, 0).new }
        .to(raise_error(ArgumentError, 'Bitwise column nonexistent must be an integer database column'))
    end
  end

  context 'when instantiating more than once' do
    it 'does not inspect the table again after a successful validation' do
      model = define.call(:regular, 0)
      model.new
      allow(model).to(receive(:columns_hash).and_call_original)
      model.new

      expect(model).not_to(have_received(:columns_hash))
    end

    it 'keeps rejecting a mapping that does not fit' do
      model = define.call(:tiny, 40)
      capture_error { model.new }

      expect { model.new }
        .to(raise_error(ArgumentError, /has limit of \d+ bytes/))
    end
  end

  context 'with several bitwise columns where only one does not fit' do
    let(:model) do
      build_model('capacity_records') do
        bitwise :regular, { flag: 0 }
        bitwise :tiny, { flag_two: 40 }
      end
    end

    it 'rejects the column that does not fit' do
      expect { model.new }
        .to(raise_error(ArgumentError, /Bitwise column tiny has limit of \d+ bytes/))
    end

    it 'keeps rejecting it after the column that fits was already validated' do
      capture_error { model.new }

      expect { model.new }
        .to(raise_error(ArgumentError, /Bitwise column tiny has limit of \d+ bytes/))
    end
  end

  context 'when the database connection is not active' do
    let(:model) { define.call(:tiny, 40) }

    it 'does not raise, so the application can boot without a database' do
      allow(model.connection).to(receive(:active?).and_return(false))

      expect { model.new }
        .not_to(raise_error)
    end

    it 'validates later, once the connection is active' do
      allow(model.connection).to(receive(:active?).and_return(false))
      model.new
      allow(model.connection).to(receive(:active?).and_call_original)

      expect { model.new }
        .to(raise_error(ArgumentError, /has limit of \d+ bytes/))
    end
  end

  context 'when introspecting the table fails unexpectedly' do
    let(:model) { define.call(:tiny, 40) }

    it 'does not raise and validates again on the next instantiation' do
      allow(model.connection).to(receive(:active?).and_raise(ActiveRecord::ConnectionNotEstablished, 'database gone'))
      model.new
      allow(model.connection).to(receive(:active?).and_call_original)

      expect { model.new }
        .to(raise_error(ArgumentError, /has limit of \d+ bytes/))
    end
  end

  context 'with an empty mapping' do
    it 'needs no capacity' do
      model = build_model('capacity_records') { bitwise(:tiny, {}) }

      expect(model.new.tiny).to(eq([]))
    end

    it 'marks the definition as validated' do
      model = build_model('capacity_records') { bitwise(:tiny, {}) }
      model.new

      expect(model.bitwise_definitions.fetch(:tiny)).to(include(validated: true))
    end
  end

  context 'with a mapping whose highest position is neither its first, last nor lowest' do
    let(:message) do
      limit = build_model('capacity_records').columns_hash['tiny'].limit
      "Bitwise column tiny has limit of #{limit} bytes (max #{{ 1 => 7, 2 => 15 }.fetch(limit)} flags), " \
        'but mapping requires bit shift position 30.'
    end

    it 'checks the highest position' do
      model = build_model('capacity_records') { bitwise(:tiny, { a: 0, b: 30, c: 2 }) }

      expect { model.new }
        .to(raise_error(ArgumentError, message))
    end
  end

  context 'when a record of the model was created before' do
    it 'does not look at the table again' do
      model = define.call(:regular, 0)
      model.new
      allow(model).to(receive(:table_exists?).and_call_original)
      model.new

      expect(model).not_to(have_received(:table_exists?))
    end
  end

  context 'when the table cannot be inspected' do
    let(:model) { define.call(:tiny, 30) }

    it 'tolerates that and checks again for the next record' do
      allow(model.connection).to(receive(:active?).and_raise(ActiveRecord::ConnectionNotEstablished))
      model.new
      allow(model.connection).to(receive(:active?).and_call_original)

      expect { model.new }
        .to(raise_error(ArgumentError, /Bitwise column tiny has limit of/))
    end
  end

  context 'when the table does not exist yet' do
    let(:model) { define.call(:tiny, 30) }

    it 'postpones the check until it does' do
      allow(model).to(receive(:table_exists?).and_return(false))
      model.new
      allow(model).to(receive(:table_exists?).and_call_original)

      expect { model.new }
        .to(raise_error(ArgumentError, /Bitwise column tiny has limit of/))
    end
  end

  context 'when the connection is not active' do
    let(:model) { define.call(:tiny, 30) }

    it 'postpones the check until it is' do
      allow(model.connection).to(receive(:active?).and_return(false))
      model.new
      allow(model.connection).to(receive(:active?).and_call_original)

      expect { model.new }
        .to(raise_error(ArgumentError, /Bitwise column tiny has limit of/))
    end
  end

  context 'with a mapping whose first position fits and a later one does not' do
    it 'rejects it, naming the highest position' do
      model = build_model('capacity_records') { bitwise(:tiny, { low: 1, high: 40 }) }

      expect { model.new }
        .to(raise_error(ArgumentError, /requires bit shift position 40\./))
    end
  end

  context 'when a validated mapping is changed afterwards' do
    it 'does not check the column again' do
      model = define.call(:tiny, 0)
      model.new
      model.bitwise_definitions[:tiny][:mapping] = { flag: 40 }

      expect { model.new }
        .not_to(raise_error)
    end
  end

  describe 'the class-level record of a completed validation' do
    let(:validation) { ActiveRecord::Bitwise::InstanceMethods::ColumnValidation                }
    let(:recorded)   { ->(model) { model.instance_variable_get(:@_bitwise_columns_validated) } }

    it 'is set once every column is validated' do
      model = define.call(:regular, 0)
      model.new

      expect(recorded.call(model)).to(be(true))
    end

    it 'is not set while a column could not be validated' do
      model = define.call(:regular, 0).tap { |two_columns| two_columns.bitwise(:small, { other_flag: 0 }) }
      model.bitwise_definitions[:regular][:validated] = true
      allow(model).to(receive(:columns_hash).and_raise(ActiveRecord::StatementInvalid))
      validation.new(model).call

      expect(recorded.call(model)).to(be_nil)
    end

    it 'is not set for a model without bitwise columns' do
      model = build_model('capacity_records')
      validation.new(model).call

      expect(recorded.call(model)).to(be_nil)
    end
  end
end
