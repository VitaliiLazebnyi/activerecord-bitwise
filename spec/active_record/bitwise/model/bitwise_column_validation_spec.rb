# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#bitwise' do
  # Validation of the column against the mapping happens lazily, on first instantiation.
  # A signed column of N bytes holds N * 8 - 1 flags (positions 0..N * 8 - 2): the sign bit is
  # never used. A column without a byte limit is a 4-byte INTEGER.
  let(:define) do
    lambda do |column, position|
      build_model('capacity_records') { bitwise column, { flag: position } }
    end
  end

  [
    { column: :tiny, limit: 1 },
    { column: :small, limit: 2 },
    { column: :medium, limit: 3 },
    { column: :regular, limit: 4 },
    { column: :big, limit: 8 }
  ].each do |tier|
    context "with a #{tier[:limit]}-byte column" do
      let(:column_limit) { build_model('capacity_records').columns_hash[tier[:column].to_s].limit || 4 }
      # The byte size the database actually reports (PostgreSQL widens 1 byte to 2 and 3 to 4).
      let(:usable_flags) { (column_limit * 8) - 1 }

      it 'accepts the highest bit position that fits' do
        expect { define.call(tier[:column], usable_flags - 1).new }.not_to raise_error
      end

      # An 8-byte column fits every position the mapping allows, so there is nothing to reject.
      unless tier[:limit] == 8
        it 'rejects the first bit position that does not fit' do
          message = "Bitwise column #{tier[:column]} has limit of #{column_limit} bytes " \
                    "(max #{usable_flags} flags), but mapping requires bit shift position #{usable_flags}."

          expect { define.call(tier[:column], usable_flags).new }.to raise_error(ArgumentError, message)
        end
      end

      it 'stores the highest flag exactly' do
        record = define.call(tier[:column], usable_flags - 1).create!(tier[:column] => [:flag])

        expect(raw_value(record, tier[:column])).to eq(1 << (usable_flags - 1))
      end
    end
  end

  # A 5-byte column is not a size any database offers natively (MySQL and PostgreSQL widen it to
  # BIGINT); where it is kept (SQLite) the gem assumes the 4-byte capacity of a plain INTEGER.
  context "with an unusual byte size (reported as #{DatabaseHelpers.column_limit('capacity_records', 'odd')} bytes)" do
    let(:odd_flags) { DatabaseHelpers.column_limit('capacity_records', 'odd') == 5 ? 31 : 63 }

    it 'accepts the highest bit position that fits' do
      expect { define.call(:odd, odd_flags - 1).new }.not_to raise_error
    end

    if DatabaseHelpers.column_limit('capacity_records', 'odd') == 5
      it 'rejects the first bit position that does not fit' do
        message = 'Bitwise column odd has limit of 5 bytes (max 31 flags), but mapping requires bit shift position 31.'

        expect { define.call(:odd, 31).new }.to raise_error(ArgumentError, message)
      end
    end
  end

  context 'with the default (4-byte) capacity on SQLite' do
    it 'allows 31 flags (positions 0..30)' do
      expect { define.call(:regular, 30).new }.not_to raise_error
    end
  end

  context 'with a column that is not an integer' do
    it 'raises ArgumentError' do
      expect { define.call(:label, 0).new }
        .to raise_error(ArgumentError, 'Bitwise column label must be an integer database column')
    end
  end

  context 'with a column that does not exist' do
    it 'raises ArgumentError' do
      expect { define.call(:nonexistent, 0).new }
        .to raise_error(ArgumentError, 'Bitwise column nonexistent must be an integer database column')
    end
  end

  context 'when instantiating more than once' do
    it 'does not inspect the table again after a successful validation' do
      model = define.call(:regular, 0)
      model.new
      allow(model).to receive(:columns_hash).and_call_original
      model.new

      expect(model).not_to have_received(:columns_hash)
    end

    it 'keeps rejecting a mapping that does not fit' do
      model = define.call(:tiny, 40)
      capture_error { model.new }

      expect { model.new }.to raise_error(ArgumentError, /has limit of \d+ bytes/)
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
      expect { model.new }.to raise_error(ArgumentError, /Bitwise column tiny has limit of \d+ bytes/)
    end

    it 'keeps rejecting it after the column that fits was already validated' do
      capture_error { model.new }

      expect { model.new }.to raise_error(ArgumentError, /Bitwise column tiny has limit of \d+ bytes/)
    end
  end

  context 'when the database connection is not active' do
    it 'does not raise, so the application can boot without a database' do
      model = define.call(:tiny, 40)
      allow(model.connection).to receive(:active?).and_return(false)

      expect { model.new }.not_to raise_error
    end

    it 'validates later, once the connection is active' do
      model = define.call(:tiny, 40)
      allow(model.connection).to receive(:active?).and_return(false)
      model.new
      allow(model.connection).to receive(:active?).and_call_original

      expect { model.new }.to raise_error(ArgumentError, /has limit of \d+ bytes/)
    end
  end

  context 'when introspecting the table fails unexpectedly' do
    it 'does not raise and validates again on the next instantiation' do
      model = define.call(:tiny, 40)
      allow(model.connection).to receive(:active?).and_raise(ActiveRecord::ConnectionNotEstablished, 'database gone')
      model.new
      allow(model.connection).to receive(:active?).and_call_original

      expect { model.new }.to raise_error(ArgumentError, /has limit of \d+ bytes/)
    end
  end

  context 'with an empty mapping' do
    it 'needs no capacity' do
      expect(build_model('capacity_records') { bitwise :tiny, {} }.new.tiny).to eq([])
    end

    it 'marks the definition as validated' do
      model = build_model('capacity_records') { bitwise :tiny, {} }
      model.new

      expect(model.bitwise_definitions.fetch(:tiny)).to include(validated: true)
    end
  end

  context 'with a mapping whose highest position is neither its first, last nor lowest' do
    it 'checks the highest position' do
      limit = build_model('capacity_records').columns_hash['tiny'].limit
      message = "Bitwise column tiny has limit of #{limit} bytes (max #{{ 1 => 7, 2 => 15 }.fetch(limit)} flags), " \
                'but mapping requires bit shift position 30.'
      model = build_model('capacity_records') { bitwise :tiny, { a: 0, b: 30, c: 2 } }

      expect { model.new }.to raise_error(ArgumentError, message)
    end
  end

  context 'when a record of the model was created before' do
    it 'does not look at the table again' do
      model = define.call(:regular, 0)
      model.new
      allow(model).to receive(:table_exists?).and_call_original
      model.new

      expect(model).not_to have_received(:table_exists?)
    end
  end

  context 'when the table cannot be inspected' do
    let(:model) { define.call(:tiny, 30) }

    it 'tolerates that and checks again for the next record' do
      allow(model.connection).to receive(:active?).and_raise(ActiveRecord::ConnectionNotEstablished)
      model.new
      allow(model.connection).to receive(:active?).and_call_original

      expect { model.new }.to raise_error(ArgumentError, /Bitwise column tiny has limit of/)
    end
  end

  context 'when the table does not exist yet' do
    let(:model) { define.call(:tiny, 30) }

    it 'postpones the check until it does' do
      allow(model).to receive(:table_exists?).and_return(false)
      model.new
      allow(model).to receive(:table_exists?).and_call_original

      expect { model.new }.to raise_error(ArgumentError, /Bitwise column tiny has limit of/)
    end
  end

  context 'when the connection is not active' do
    let(:model) { define.call(:tiny, 30) }

    it 'postpones the check until it is' do
      allow(model.connection).to receive(:active?).and_return(false)
      model.new
      allow(model.connection).to receive(:active?).and_call_original

      expect { model.new }.to raise_error(ArgumentError, /Bitwise column tiny has limit of/)
    end
  end
end
