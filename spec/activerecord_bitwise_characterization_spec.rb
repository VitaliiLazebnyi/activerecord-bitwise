# frozen_string_literal: true

require 'spec_helper'

# Characterization specs: they pin the exact, currently observable public behavior
# of the gem (exact values, exception classes AND messages, boundaries) so that
# dependency upgrades and refactors cannot silently change it.

class CharUser < ActiveRecord::Base
  self.table_name = 'users'

  bitwise :roles, { admin: 0, _legacy: 1, author: 2, subscriber: 3 }
  bitwise :permissions, { read: 0, manage: 1 }, default: [:read]
  bitwise :legacy_roles, %i[admin moderator author subscriber], prefix: :legacy

  validates :roles, bitwise: true
end

class CharTinyUser < ActiveRecord::Base
  self.table_name = 'users'

  bitwise :custom_limits, { first: 0, last: 6 }
end

class CharPost < ActiveRecord::Base
  self.table_name = 'etl_records'

  bitwise :legacy_flags, { draft: 0, pinned: 1 }
end

RSpec.describe ActiveRecord::Bitwise, 'characterization' do
  def raw(record, column = :roles)
    ActiveRecord::Base.connection.select_value("SELECT #{column} FROM users WHERE id = #{record.id}")
  end

  def plant(record, value, column = :roles)
    ActiveRecord::Base.connection.execute("UPDATE users SET #{column} = #{value.nil? ? 'NULL' : value} WHERE id = #{record.id}")
    record.reload
  end

  def anonymous_model(table = 'users', &block)
    Class.new(ActiveRecord::Base) do
      self.table_name = table
      def self.name = 'AnonymousModel'
    end.tap { |klass| klass.class_eval(&block) if block }
  end

  before do
    ActiveRecord::Base.connection.execute('DELETE FROM users')
    ActiveRecord::Base.connection.execute('DELETE FROM etl_records')
  end

  describe ActiveRecord::Bitwise::Type do
    let(:type) { CharUser.attribute_types['roles'] }

    describe '#cast' do
      it 'returns nil for nil' do
        expect(type.cast(nil)).to be_nil
      end

      it 'treats an Integer as a bitmask and carries the raw value' do
        casted = type.cast(0b1101)
        expect(casted).to eq(%i[admin author subscriber])
        expect(casted).to be_frozen
        expect(casted.instance_variable_get(:@_bitwise_raw_value)).to eq(0b1101)
      end

      it 'treats a bare numeric String as a bitmask' do
        expect(type.cast('5')).to eq(%i[admin author])
      end

      it 'treats a mapped name String as a flag, not a bitmask' do
        expect(type.cast('admin')).to eq([:admin])
      end

      it 'treats an unmapped, non-numeric String as an unknown flag kept as a String' do
        expect(type.cast('hacker')).to eq(['hacker'])
      end

      it 'does not treat a negative numeric string as a bitmask' do
        expect(type.cast('-1')).to eq(['-1'])
      end

      it 'symbolizes mapped strings and keeps unmapped values as strings' do
        expect(type.cast(['admin', :author, 'nope'])).to eq([:admin, :author, 'nope'])
      end

      it 'drops nil and empty strings but keeps other falsy-looking values as names' do
        expect(type.cast([nil, '', 'admin'])).to eq([:admin])
        expect(type.cast([0])).to eq(['0'])
      end

      it 'de-duplicates by string form, keeping the first occurrence' do
        expect(type.cast([:admin, 'admin', :admin])).to eq([:admin])
      end

      it 'returns a frozen array' do
        expect(type.cast([:admin])).to be_frozen
      end

      it 'returns an empty frozen array for an empty array' do
        expect(type.cast([])).to eq([])
        expect(type.cast([])).to be_frozen
      end

      it 'accepts exactly MAX_ARRAY_SIZE elements and rejects one more' do
        expect(type.cast(Array.new(100) { |i| "v#{i}" }).size).to eq(100)
        expect { type.cast(Array.new(101) { |i| "v#{i}" }) }
          .to raise_error(ArgumentError, 'Array size cannot exceed 100')
      end

      it 'counts only non-empty elements toward the size limit' do
        values = Array.new(100) { |i| "v#{i}" } + [nil, '']
        expect(type.cast(values).size).to eq(100)
      end

      [{ a: 1 }, true, false].each do |bad|
        it "rejects #{bad.inspect} with a descriptive message" do
          expect { type.cast(bad) }
            .to raise_error(ArgumentError, "cannot cast #{bad.inspect} to a bitwise flag array for column roles")
        end
      end

      it 'wraps a single Symbol into an array' do
        expect(type.cast(:author)).to eq([:author])
      end

      it 'returns an already-stamped frozen array as-is (same object)' do
        stamped = type.cast(3)
        expect(type.cast(stamped)).to equal(stamped)
      end

      it 'preserves the raw marker of an unfrozen stamped array' do
        input = [:admin]
        input.instance_variable_set(:@_bitwise_raw_value, 0b10001)
        expect(type.cast(input).instance_variable_get(:@_bitwise_raw_value)).to eq(0b10001)
      end

      it 'does not stamp a raw marker on plain arrays' do
        expect(type.cast([:admin]).instance_variable_defined?(:@_bitwise_raw_value)).to be(false)
      end
    end

    describe '#deserialize' do
      it 'returns the frozen shared empty array for nil' do
        result = type.deserialize(nil)
        expect(result).to eq([])
        expect(result).to be_frozen
        expect(result.instance_variable_get(:@_bitwise_raw_value)).to eq(0)
      end

      it 'maps each set bit to its key in mapping order' do
        expect(type.deserialize(0b1111)).to eq(%i[admin _legacy author subscriber])
      end

      it 'keeps unmapped bits only in the raw marker' do
        result = type.deserialize(0b1_0000_0001)
        expect(result).to eq([:admin])
        expect(result.instance_variable_get(:@_bitwise_raw_value)).to eq(0b1_0000_0001)
      end

      it 'coerces numeric strings (raw SQLite reads)' do
        expect(type.deserialize('6')).to eq(%i[_legacy author])
      end

      it 'returns an empty array for zero' do
        expect(type.deserialize(0)).to eq([])
      end

      it 're-wraps an Array input, deriving the raw value through serialize' do
        result = type.deserialize(%i[admin author])
        expect(result).to eq(%i[admin author])
        expect(result.instance_variable_get(:@_bitwise_raw_value)).to eq(0b101)
        expect(result).to be_frozen
      end

      it 'raises Error at recursion depth 2 and always restores the depth afterwards' do
        Thread.current[:ar_bitwise_deserialize_depth] = 2
        expect { type.deserialize(1) }
          .to raise_error(ActiveRecord::Bitwise::Error, 'System recursion limit exceeded in deserialize')
        expect(Thread.current[:ar_bitwise_deserialize_depth]).to eq(2)
      ensure
        Thread.current[:ar_bitwise_deserialize_depth] = nil
      end

      it 'allows depth 1 and restores it' do
        Thread.current[:ar_bitwise_deserialize_depth] = 1
        expect(type.deserialize(1)).to eq([:admin])
        expect(Thread.current[:ar_bitwise_deserialize_depth]).to eq(1)
      ensure
        Thread.current[:ar_bitwise_deserialize_depth] = nil
      end

      it 'leaves the depth cleared after a normal call' do
        type.deserialize(1)
        expect(Thread.current[:ar_bitwise_deserialize_depth]).to eq(0)
      ensure
        Thread.current[:ar_bitwise_deserialize_depth] = nil
      end
    end

    describe '#serialize' do
      it 'returns nil for nil' do
        expect(type.serialize(nil)).to be_nil
      end

      it 'passes Integers through untouched, even negative or huge ones' do
        expect(type.serialize(-5)).to eq(-5)
        expect(type.serialize(2**70)).to eq(2**70)
      end

      it 'ORs bits for mapped flags' do
        expect(type.serialize(%i[admin subscriber])).to eq(0b1001)
      end

      it 'accepts strings and symbols interchangeably and ignores unknown flags' do
        expect(type.serialize(['author', :admin, 'nope'])).to eq(0b101)
      end

      it 'is idempotent for duplicates' do
        expect(type.serialize(%i[admin admin])).to eq(1)
      end

      it 'returns 0 for an empty array' do
        expect(type.serialize([])).to eq(0)
      end

      it 'merges unmapped bits from the raw marker' do
        marked = [:admin]
        marked.instance_variable_set(:@_bitwise_raw_value, 0b1_0000_0110)
        # known mask is 0b1111, so 0b110 (known) is replaced by the flags, 0b1_0000_0000 survives
        expect(type.serialize(marked)).to eq(0b1_0000_0001)
      end

      it 'coerces a numeric-string raw marker' do
        marked = []
        marked.instance_variable_set(:@_bitwise_raw_value, '256')
        expect(type.serialize(marked)).to eq(256)
      end

      it 'treats a non-numeric raw marker as zero' do
        marked = [:admin]
        marked.instance_variable_set(:@_bitwise_raw_value, Object.new)
        expect(type.serialize(marked)).to eq(1)
      end

      it 'supports the highest bit position (62) without overflow' do
        wide = described_class.new(:wide, { top: 62, bottom: 0 }, [])
        expect(wide.serialize([:top])).to eq(1 << 62)
        expect(wide.serialize(%i[top bottom])).to eq((1 << 62) | 1)
        expect(wide.deserialize(1 << 62)).to eq([:top])
      end
    end

    describe 'readers' do
      it 'exposes configuration' do
        expect(type.column_name).to eq(:roles)
        expect(type.mapping).to eq(admin: 0, _legacy: 1, author: 2, subscriber: 3)
        expect(type.known_mask).to eq(0b1111)
        expect(type.mapping_strings).to eq(%w[admin _legacy author subscriber])
        expect(type.mapping_strings).to be_frozen
        expect(type.default).to eq([])
        expect(CharUser.attribute_types['permissions'].default).to eq([:read])
      end

      it 'converts a String column name to a Symbol and defaults nil to []' do
        built = described_class.new('flags', { a: 0 }, nil)
        expect(built.column_name).to eq(:flags)
        expect(built.default).to eq([])
        expect(built.known_mask).to eq(1)
      end
    end
  end

  describe 'macro configuration errors' do
    it 'rejects a mapping that is neither Hash nor Array' do
      # Sorbet's runtime signature rejects it before the macro's own guard can run.
      expect { anonymous_model { bitwise :roles, 'admin' } }
        .to raise_error(TypeError, /Parameter 'mapping': Expected type/)
    end

    [-1, 63, 'abc', 1.5, nil, :one].each do |bad|
      it "rejects bit position #{bad.inspect}" do
        message = "Bitwise column roles mapping key admin has invalid bit position #{bad.inspect}. " \
                  'Positions must be Integers between 0 and 62; they are bit POSITIONS (1 << position), not masks.'
        expect { anonymous_model { bitwise :roles, { admin: bad } } }
          .to raise_error(ActiveRecord::Bitwise::ConfigurationError, message)
      end
    end

    it 'accepts boundary positions 0 and 62 and numeric-string positions' do
      model = anonymous_model { bitwise :roles, { a: 0, b: 62, c: '5' } }
      expect(model.bitwise_schema(:roles)).to eq(a: 0, b: 62, c: 5)
    end

    it 'rejects two keys sharing a bit position' do
      expect { anonymous_model { bitwise :roles, { a: 1, b: 1 } } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /assigns the same bit position to multiple keys: #{Regexp.escape({ a: 1, b: 1 }.inspect)}\. Values are bit POSITIONS/)
    end

    it 'rejects keys that collide after symbolization' do
      expect { anonymous_model { bitwise :roles, { 'a' => 0, a: 1 } } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError,
                        'Bitwise column roles mapping contains duplicate keys after symbolization')
    end

    it 'rejects duplicate entries in an Array mapping' do
      expect { anonymous_model { bitwise :roles, %i[a a] } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /duplicate keys after symbolization/)
    end

    it 'rejects defaults that are not in the mapping' do
      expect { anonymous_model { bitwise :roles, { a: 0 }, default: %i[a zzz] } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError,
                        'Bitwise column roles default contains values not present in the mapping: ["zzz"]')
    end

    it 'rejects keys shadowing a database column' do
      expect { anonymous_model { bitwise :roles, { permissions: 0 } } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError,
                        "Bitwise column roles mapping key permissions would shadow the database column or attribute 'permissions'. Use prefix:/suffix: to disambiguate.")
    end

    it 'rejects a key equal to the column name' do
      expect { anonymous_model { bitwise :roles, { roles: 0 } } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /would shadow the database column or attribute 'roles'/)
    end

    it 'rejects keys that collide with core ActiveRecord methods' do
      expect { anonymous_model { bitwise :roles, { save: 0 } } }
        .to raise_error(ArgumentError, 'Bitwise column roles mapping key save generates method #save! which collides with core ActiveRecord::Base instance methods.')
    end

    it 'rejects keys already generated by another bitwise column' do
      expect do
        anonymous_model do
          bitwise :roles, { admin: 0 }
          bitwise :legacy_roles, { admin: 0 }
        end
      end.to raise_error(ActiveRecord::Bitwise::ConfigurationError,
                         /generates method #admin\? which is already defined by another bitwise column/)
    end

    it 'allows re-declaring the same column (its own methods are not collisions)' do
      expect do
        anonymous_model do
          bitwise :roles, { admin: 0 }
          bitwise :roles, { admin: 0, author: 1 }
        end
      end.not_to raise_error
    end

    it 'is a subclass of ArgumentError for both configuration and unknown-value errors' do
      expect(ActiveRecord::Bitwise::ConfigurationError.ancestors).to include(ArgumentError)
      expect(ActiveRecord::Bitwise::UnknownValueError.ancestors).to include(ArgumentError)
      expect(ActiveRecord::Bitwise::NotSupportedError.ancestors).to include(ActiveRecord::Bitwise::Error)
      expect(ActiveRecord::Bitwise::Error.ancestors).to include(StandardError)
    end

    it 'applies prefix: true / suffix: true using the singular column name' do
      model = anonymous_model do
        bitwise :roles, { admin: 0 }, prefix: true
        bitwise :permissions, { read: 0 }, suffix: true
      end
      record = model.new
      expect(record).to respond_to(:role_admin?, :read_permission?)
      expect(record).not_to respond_to(:admin?, :read?)
    end

    it 'applies prefix: false and nil as no affix' do
      model = anonymous_model { bitwise :roles, { admin: 0 }, prefix: false }
      expect(model.new).to respond_to(:admin?)
    end

    it 'applies string prefixes and suffixes verbatim' do
      model = anonymous_model { bitwise :roles, { admin: 0 }, prefix: 'is', suffix: 'now' }
      expect(model.new).to respond_to(:is_admin_now?, :is_admin_now=, :is_admin_now!)
    end

    it 'supports Array mappings where the index is the bit position' do
      expect(CharUser.bitwise_schema(:legacy_roles)).to eq(admin: 0, moderator: 1, author: 2, subscriber: 3)
    end

    it 'returns a defensive copy from bitwise_schema and nil for unknown columns' do
      CharUser.bitwise_schema(:roles)[:hacked] = 9
      expect(CharUser.bitwise_schema('roles')).to eq(admin: 0, _legacy: 1, author: 2, subscriber: 3)
      expect(CharUser.bitwise_schema(:missing)).to be_nil
    end

    it 'gives subclasses independent copies of the definitions' do
      child = Class.new(CharUser) { def self.name = 'CharChild' }
      child.bitwise :extra_roles, { a: 0 } if false # rubocop:disable Lint/LiteralAsCondition
      child.bitwise_definitions[:roles][:mapping][:injected] = 9
      expect(CharUser.bitwise_definitions[:roles][:mapping]).not_to have_key(:injected)
    end
  end

  describe 'column validation (lazy, on first initialization)' do
    it 'rejects a non-integer column with an exact message' do
      model = anonymous_model { bitwise :type, { a: 0 } }
      expect { model.new }.to raise_error(ArgumentError, 'Bitwise column type must be an integer database column')
    end

    it 'rejects a bit position that does not fit the column limit' do
      model = anonymous_model { bitwise :custom_limits, { a: 7 } }
      expect { model.new }.to raise_error(
        ArgumentError,
        'Bitwise column custom_limits has limit of 1 bytes (max 7 flags), but mapping requires bit shift position 7.'
      )
    end

    it 'accepts the highest position that fits (6 on a 1-byte column)' do
      expect { CharTinyUser.new }.not_to raise_error
      record = CharTinyUser.create!(custom_limits: %i[first last])
      expect(raw(record, :custom_limits).to_i).to eq(0b100_0001)
    end

    it 'rejects a missing column' do
      model = anonymous_model { bitwise :nonexistent, { a: 0 } }
      expect { model.new }.to raise_error(ArgumentError, 'Bitwise column nonexistent must be an integer database column')
    end
  end

  describe 'getters, setters and defaults' do
    it 'applies defaults to new records only' do
      expect(CharUser.new.permissions).to eq([:read])
      expect(CharUser.new(permissions: []).permissions).to eq([])
      persisted = CharUser.create!(permissions: [])
      expect(CharUser.find(persisted.id).permissions).to eq([])
    end

    it 'does not resurrect defaults for a persisted NULL column' do
      record = CharUser.create!(roles: [:admin])
      plant(record, nil)
      expect(record.roles).to eq([])
    end

    it 'returns frozen arrays from the getter' do
      expect(CharUser.new(roles: [:admin]).roles).to be_frozen
      expect(CharUser.new.roles).to be_frozen
    end

    it 'rejects mutation of the returned array' do
      record = CharUser.new(roles: [:admin])
      expect { record.roles << :author }.to raise_error(FrozenError)
      expect(record.roles).to eq([:admin])
    end

    it 'accepts strings, symbols, integers, nil and mixed input via the setter' do
      record = CharUser.new
      record.roles = ['admin', :author]
      expect(record.roles).to eq(%i[admin author])
      record.roles = 8
      expect(record.roles).to eq([:subscriber])
      record.roles = nil
      expect(record.roles).to eq([])
      record.roles = 'admin'
      expect(record.roles).to eq([:admin])
    end

    it 'stores nil as NULL when assigned nil on a nullable column' do
      record = CharUser.create!(roles: [:admin])
      record.update!(roles: nil)
      expect(raw(record)).to be_nil
    end

    it 'persists exact integer bitmasks' do
      record = CharUser.create!(roles: %i[admin subscriber])
      expect(raw(record)).to eq(0b1001)
      record.update!(roles: [])
      expect(raw(record)).to eq(0)
    end

    it 'raises on Hash, true and false assignment' do
      record = CharUser.new
      expect { record.roles = { a: 1 } }.to raise_error(ArgumentError, "cannot cast #{{ a: 1 }.inspect} to a bitwise flag array for column roles")
      expect { record.roles = true }.to raise_error(ArgumentError, 'cannot cast true to a bitwise flag array for column roles')
      expect { record.roles = false }.to raise_error(ArgumentError, 'cannot cast false to a bitwise flag array for column roles')
    end

    it 'drops unknown values from the getter after create and never persists them' do
      record = anonymous_model { bitwise :roles, { admin: 0 } }.create!(roles: [:admin, 'bogus'])
      expect(record.roles).to eq([:admin])
      expect(raw(record)).to eq(1)
      expect(record.reload.roles).to eq([:admin])
    end
  end

  describe 'per-flag methods' do
    let(:record) { CharUser.create!(roles: [], permissions: []) }

    it 'reports flags with predicate methods' do
      record.roles = [:author]
      expect(record.author?).to be(true)
      expect(record.admin?).to be(false)
      expect(record.legacy_author?).to be(false)
    end

    %w[0 false off f F FALSE OFF].each do |falsy|
      it "disables a flag when assigned #{falsy.inspect}" do
        record.admin = true
        record.admin = falsy
        expect(record.admin?).to be(false)
      end
    end

    [true, 1, '1', 'true', 'on', 't', 'no', 'anything'].each do |truthy|
      it "enables a flag when assigned #{truthy.inspect}" do
        record.admin = truthy
        expect(record.admin?).to be(true)
      end
    end

    it 'treats nil and empty string as disabling (Rails checkbox semantics)' do
      record.admin = true
      record.admin = nil
      expect(record.roles).to eq([])
      record.admin = true
      record.admin = ''
      expect(record.roles).to eq([])
    end

    it 'does not duplicate an already-enabled flag and keeps other flags' do
      record.roles = %i[admin author]
      record.admin = true
      expect(record.roles).to eq(%i[admin author])
      record.author = false
      expect(record.roles).to eq([:admin])
    end

    it 'preserves unmapped bits across flag assignment' do
      plant(record, 0b1_0000_0001)
      record.author = true
      record.save!
      expect(raw(record)).to eq(0b1_0000_0101)
    end

    it 'saves immediately with the bang method and is idempotent' do
      record.author!
      expect(raw(record)).to eq(0b100)
      record.author!
      expect(raw(record)).to eq(0b100)
    end

    it 'raises RecordInvalid from the bang method when the record is invalid' do
      invalid = anonymous_model do
        bitwise :roles, { admin: 0 }
        validates :permissions, numericality: { greater_than: 100 }
      end.new
      expect { invalid.admin! }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'dirty tracking' do
    it 'is not changed when assigning an equal value' do
      record = CharUser.create!(roles: [:admin])
      record.roles = [:admin]
      expect(record.roles_changed?).to be(false)
      expect(record.changed?).to be(false)
    end

    it 'tracks changes and exposes the previous value' do
      record = CharUser.create!(roles: [:admin])
      record.roles = %i[admin author]
      expect(record.roles_changed?).to be(true)
      expect(record.roles_was).to eq([:admin])
      expect(record.changes['roles'].last).to eq(%i[admin author])
    end

    it 'treats a reordered reassignment as a change (arrays compare in order) yet persists the same bitmask' do
      record = CharUser.create!(roles: %i[admin author])
      record.roles = %i[author admin]
      expect(record.roles_changed?).to be(true)
      record.save!
      expect(raw(record)).to eq(0b101)
    end

    it 'persists an unmapped-bits-only integer change' do
      record = CharUser.create!(roles: [:admin])
      record.roles = 0b1_0000_0001
      expect(record.roles_changed?).to be(true)
      record.save!
      expect(raw(record)).to eq(0b1_0000_0001)
    end

    it 'clears dirty state after save' do
      record = CharUser.create!(roles: [:admin])
      record.roles = [:author]
      record.save!
      expect(record.roles_changed?).to be(false)
    end
  end

  describe 'ghost (unmapped) bits' do
    let(:record) { CharUser.create!(roles: [:admin]) }

    before { plant(record, 0b11_0000_0001) }

    it 'hides ghost bits from the getter' do
      expect(record.roles).to eq([:admin])
    end

    it 'preserves ghost bits on normal updates' do
      record.update!(roles: %i[admin author])
      expect(raw(record)).to eq(0b11_0000_0101)
    end

    it 'preserves ghost bits when flags are cleared' do
      record.update!(roles: [])
      expect(raw(record)).to eq(0b11_0000_0000)
    end

    it 'drops ghost bits when nil is assigned' do
      record.update!(roles: nil)
      expect(raw(record)).to be_nil
    end

    it 'preserves ghost bits via write_attribute and []=' do
      record[:roles] = [:subscriber]
      record.save!
      expect(raw(record)).to eq(0b11_0000_1000)
      record.write_attribute(:roles, [:author])
      record.save!
      expect(raw(record)).to eq(0b11_0000_0100)
    end

    it 'replaces everything with an explicit integer assignment' do
      record.update!(roles: 2)
      expect(raw(record)).to eq(2)
    end

    it 'drops ghost bits on dup' do
      copy = record.dup
      copy.save!
      expect(raw(copy)).to eq(1)
    end

    it 'refreshes the raw cache on reload' do
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = 1025 WHERE id = #{record.id}")
      record.reload
      record.update!(roles: [:author])
      expect(raw(record)).to eq(0b100_0000_0100)
    end

    it 'preserves ghost bits with update_columns for flag arrays and overwrites for integers' do
      record.update_columns(roles: [:author])
      expect(raw(record)).to eq(0b11_0000_0100)
      record.update_columns(roles: 3)
      expect(raw(record)).to eq(3)
      expect(record.roles).to eq(%i[admin _legacy])
    end

    it 'writes NULL via update_columns(nil)' do
      record.update_columns(roles: nil)
      expect(raw(record)).to be_nil
    end

    it 'passes non-bitwise columns through update_columns' do
      record.update_columns(permissions: 3, roles: [:author])
      expect(raw(record, :permissions)).to eq(3)
      expect(record.permissions).to eq(%i[read manage])
    end

    it 'supports update_column (singular) and string keys' do
      record.update_column(:roles, [:subscriber])
      expect(raw(record)).to eq(0b11_0000_1000)
      record.update_columns('roles' => [:admin])
      expect(raw(record)).to eq(0b11_0000_0001)
    end

    it 'clear_bitwise_raw_values_cache! only empties the cache: ghost bits are re-hydrated from the loaded value' do
      record.clear_bitwise_raw_values_cache!
      expect(record._bitwise_raw_cache).to eq({})
      record.update!(roles: %i[admin author])
      expect(raw(record)).to eq(0b11_0000_0101)
    end

    it 'does not re-save a stale ghost mask after a save resets the cache' do
      record.update!(roles: [:author])
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = 4 WHERE id = #{record.id}")
      record.reload.update!(roles: [:admin])
      expect(raw(record)).to eq(1)
    end
  end

  describe 'scopes' do
    let!(:rec_none) { CharUser.create!(roles: []) }
    let!(:rec_admin) { CharUser.create!(roles: [:admin]) }
    let!(:rec_author) { CharUser.create!(roles: [:author]) }
    let!(:rec_both) { CharUser.create!(roles: %i[admin author]) }
    let!(:rec_all3) { CharUser.create!(roles: %i[admin author subscriber]) }

    def ids(relation) = relation.order(:id).map(&:id)

    it 'with_ matches records containing ALL given values' do
      expect(ids(CharUser.with_roles(:admin))).to eq([rec_admin, rec_both, rec_all3].map(&:id))
      expect(ids(CharUser.with_roles(:admin, :author))).to eq([rec_both, rec_all3].map(&:id))
      expect(ids(CharUser.with_roles(%i[admin author]))).to eq([rec_both, rec_all3].map(&:id))
    end

    it 'with_ accepts strings and ignores unknown values when at least one is valid' do
      expect(ids(CharUser.with_roles('admin', 'bogus'))).to eq([rec_admin, rec_both, rec_all3].map(&:id))
    end

    it 'with_ returns nothing when every value is unknown' do
      expect(CharUser.with_roles(:bogus).to_a).to eq([])
    end

    it 'with_ returns all records when called with no values' do
      expect(CharUser.with_roles.count).to eq(5)
    end

    it 'with_ treats [] / nil / "" as empty-match (raw = 0)' do
      expect(ids(CharUser.with_roles([]))).to eq([rec_none.id])
      expect(ids(CharUser.with_roles(nil))).to eq([rec_none.id])
      expect(ids(CharUser.with_roles(''))).to eq([rec_none.id])
    end

    it 'with_ treats 0 and "0" as the empty set' do
      expect(ids(CharUser.with_roles(0))).to eq([rec_none.id])
      expect(ids(CharUser.with_roles('0'))).to eq([rec_none.id])
    end

    it 'with_any_ matches records containing ANY value' do
      expect(ids(CharUser.with_any_roles(:author, :subscriber))).to eq([rec_author, rec_both, rec_all3].map(&:id))
    end

    it 'with_any_ ignores unknown values, returns none if all unknown, all if empty' do
      expect(ids(CharUser.with_any_roles(:author, :bogus))).to eq([rec_author, rec_both, rec_all3].map(&:id))
      expect(CharUser.with_any_roles(:bogus).to_a).to eq([])
      expect(CharUser.with_any_roles.count).to eq(5)
      expect(CharUser.with_any_roles(nil, '').count).to eq(5)
    end

    it 'with_exact_ matches the exact bitmask only' do
      expect(ids(CharUser.with_exact_roles(:admin, :author))).to eq([rec_both.id])
      expect(ids(CharUser.with_exact_roles(:admin))).to eq([rec_admin.id])
    end

    it 'with_exact_ with no values matches zero, and with any unknown value matches nothing' do
      expect(ids(CharUser.with_exact_roles)).to eq([rec_none.id])
      expect(ids(CharUser.with_exact_roles(nil, ''))).to eq([rec_none.id])
      expect(CharUser.with_exact_roles(:admin, :bogus).to_a).to eq([])
    end

    it 'without_ excludes records having ANY given value' do
      expect(ids(CharUser.without_roles(:admin))).to eq([rec_none, rec_author].map(&:id))
      expect(ids(CharUser.without_roles(:admin, :author))).to eq([rec_none.id])
    end

    it 'without_ ignores unknown values and returns all when nothing valid is given' do
      expect(CharUser.without_roles(:bogus).count).to eq(5)
      expect(CharUser.without_roles.count).to eq(5)
      expect(ids(CharUser.without_roles(:admin, :bogus))).to eq([rec_none, rec_author].map(&:id))
    end

    it 'ignores ghost bits when matching mapped flags and respects them for exact matches' do
      plant(rec_admin, 0b1_0000_0001)
      expect(ids(CharUser.with_roles(:admin))).to include(rec_admin.id)
      expect(ids(CharUser.with_exact_roles(:admin))).not_to include(rec_admin.id)
    end

    it 'treats NULL as no flags' do
      plant(rec_none, nil)
      expect(CharUser.with_roles(:admin).pluck(:id)).not_to include(rec_none.id)
      expect(CharUser.without_roles(:admin).pluck(:id)).not_to include(rec_none.id) # SQL NULL & x is NULL
    end

    it 'qualifies columns so scopes keep working under joins' do
      joined = CharUser.joins('INNER JOIN etl_records ON etl_records.id = users.id')
      expect { joined.with_roles(:admin).to_a }.not_to raise_error
      expect { joined.with_any_roles(:admin).to_a }.not_to raise_error
      expect { joined.with_exact_roles(:admin).to_a }.not_to raise_error
      expect { joined.without_roles(:admin).to_a }.not_to raise_error
    end

    it 'generates SQL using the exact documented operators' do
      expect(CharUser.with_roles(:admin, :author).to_sql).to include('"users"."roles" & 5 = 5')
      expect(CharUser.with_any_roles(:admin, :author).to_sql).to include('"users"."roles" & 5 > 0')
      expect(CharUser.with_exact_roles(:admin, :author).to_sql).to include('"users"."roles" = 5')
      expect(CharUser.without_roles(:admin, :author).to_sql).to include('"users"."roles" & 5 = 0')
      expect(CharUser.with_roles(:bogus).to_sql).to include('1=0')
    end

    it 'chains scopes' do
      expect(ids(CharUser.with_roles(:admin).without_roles(:author))).to eq([rec_admin.id])
    end
  end

  describe 'where / find_by / not' do
    let!(:rec_admin) { CharUser.create!(roles: [:admin]) }
    let!(:rec_both) { CharUser.create!(roles: %i[admin author]) }

    it 'matches the exact bitmask for symbol arrays' do
      expect(CharUser.where(roles: [:admin]).map(&:id)).to eq([rec_admin.id])
      expect(CharUser.where(roles: %i[author admin]).map(&:id)).to eq([rec_both.id])
    end

    it 'accepts string keys, strings and single symbols' do
      expect(CharUser.where('roles' => 'admin').map(&:id)).to eq([rec_admin.id])
      expect(CharUser.where(roles: :admin).map(&:id)).to eq([rec_admin.id])
    end

    it 'passes Integer, nil and integer-array conditions through untouched' do
      expect(CharUser.where(roles: 1).map(&:id)).to eq([rec_admin.id])
      expect(CharUser.where(roles: [1, 5]).map(&:id)).to eq([rec_admin.id, rec_both.id])
      expect(CharUser.where(roles: nil).to_a).to eq([])
    end

    it 'maps an empty array to the empty bitmask 0' do
      zero = CharUser.create!(roles: [])
      expect(CharUser.where(roles: []).map(&:id)).to eq([zero.id])
    end

    it 'raises UnknownValueError (class and message) for unmapped values' do
      expect { CharUser.where(roles: %i[admin bogus]) }
        .to raise_error(ActiveRecord::Bitwise::UnknownValueError, 'Unknown bitwise value(s) ["bogus"] for column roles')
    end

    it 'supports find_by' do
      expect(CharUser.find_by(roles: %i[admin author])).to eq(rec_both)
    end

    it 'leaves non-bitwise columns and non-hash conditions alone' do
      expect(CharUser.where('roles = ?', 1).map(&:id)).to eq([rec_admin.id])
      expect(CharUser.where(id: rec_admin.id).map(&:id)).to eq([rec_admin.id])
    end

    it 'does not mutate the caller\'s hash' do
      conditions = { roles: [:admin] }
      CharUser.where(conditions)
      expect(conditions).to eq(roles: [:admin])
    end

    it 'serializes where.not' do
      expect(CharUser.where.not(roles: [:admin]).map(&:id)).to eq([rec_both.id])
      expect { CharUser.where.not(roles: [:bogus]) }
        .to raise_error(ActiveRecord::Bitwise::UnknownValueError, /bogus/)
    end

    it 'supports where.not with non-hash and non-bitwise arguments' do
      expect(CharUser.where.not(id: rec_admin.id).map(&:id)).to eq([rec_both.id])
    end

    it 'works on models without bitwise definitions' do
      expect(anonymous_model.where(id: 0).to_a).to eq([])
      expect(ActiveRecord::Base.connection.select_value('SELECT 1')).to eq(1)
    end
  end

  describe 'update_all' do
    let!(:rec_a) { CharUser.create!(roles: [:admin]) }
    let!(:rec_b) { CharUser.create!(roles: [:author]) }

    before { plant(rec_a, 0b1_0000_0001) }

    it 'sets flags while preserving ghost bits in every matched row' do
      CharUser.update_all(roles: [:subscriber])
      expect(raw(rec_a)).to eq(0b1_0000_1000)
      expect(raw(rec_b)).to eq(0b1000)
    end

    it 'accepts string keys and string values' do
      CharUser.update_all('roles' => ['author'])
      expect(raw(rec_a)).to eq(0b1_0000_0100)
    end

    it 'clears flags (not ghost bits) with an empty array' do
      CharUser.update_all(roles: [])
      expect(raw(rec_a)).to eq(0b1_0000_0000)
      expect(raw(rec_b)).to eq(0)
    end

    it 'writes Integers and NULL verbatim' do
      CharUser.where(id: rec_a.id).update_all(roles: 7)
      expect(raw(rec_a)).to eq(7)
      CharUser.where(id: rec_a.id).update_all(roles: nil)
      expect(raw(rec_a)).to be_nil
    end

    it 'passes Arel SQL literals through' do
      CharUser.where(id: rec_b.id).update_all(roles: Arel.sql('roles | 1'))
      expect(raw(rec_b)).to eq(0b101)
    end

    it 'raises UnknownValueError with an exact message and changes nothing' do
      expect { CharUser.update_all(roles: %i[admin bogus]) }.to raise_error(
        ActiveRecord::Bitwise::UnknownValueError,
        'Unknown bitwise value(s) ["bogus"] for column roles; refusing to zero unrecognized flags via update_all'
      )
      expect(raw(rec_b)).to eq(0b100)
    end

    it 'updates NULL rows' do
      plant(rec_b, nil)
      CharUser.where(id: rec_b.id).update_all(roles: [:admin])
      expect(raw(rec_b)).to eq(1)
    end

    it 'passes string SQL and non-bitwise hashes through' do
      CharUser.where(id: rec_b.id).update_all('permissions = 3')
      expect(raw(rec_b, :permissions)).to eq(3)
      CharUser.where(id: rec_b.id).update_all(permissions: 1)
      expect(raw(rec_b, :permissions)).to eq(1)
    end

    it 'mixes bitwise and ordinary columns in one hash' do
      CharUser.where(id: rec_b.id).update_all(roles: [:admin], permissions: 2)
      expect(raw(rec_b)).to eq(1)
      expect(raw(rec_b, :permissions)).to eq(2)
    end

    it 'returns the affected row count' do
      expect(CharUser.update_all(roles: [:admin])).to eq(2)
    end

    it 'does not let a smuggled raw marker inject bits' do
      marked = [:admin]
      marked.instance_variable_set(:@_bitwise_raw_value, 0b1111_0000_0000)
      CharUser.where(id: rec_b.id).update_all(roles: marked)
      expect(raw(rec_b)).to eq(1)
    end
  end

  describe 'class-level atomic methods' do
    let!(:a) { CharUser.create!(roles: [:admin]) }
    let!(:b) { CharUser.create!(roles: [:author]) }

    it 'adds flags to the given records only' do
      CharUser.add_roles!(:subscriber, records: [a])
      expect(raw(a)).to eq(0b1001)
      expect(raw(b)).to eq(0b100)
    end

    it 'accepts a single record, a single id and arrays of ids' do
      CharUser.add_roles!(:author, records: a)
      CharUser.add_roles!(:subscriber, records: b.id)
      CharUser.add_roles!(:admin, records: [a.id, b.id])
      expect(raw(a)).to eq(0b101)
      expect(raw(b)).to eq(0b1101)
    end

    it 'removes flags and is a no-op for flags not set' do
      CharUser.remove_roles!(:admin, :subscriber, records: [a])
      expect(raw(a)).to eq(0)
      expect(raw(b)).to eq(0b100)
    end

    it 'accepts nested arrays and strings' do
      CharUser.add_roles!(%w[author subscriber], records: a)
      expect(raw(a)).to eq(0b1101)
    end

    it 'preserves ghost bits' do
      plant(a, 0b1_0000_0001)
      CharUser.remove_roles!(:admin, records: a)
      expect(raw(a)).to eq(0b1_0000_0000)
      CharUser.add_roles!(:author, records: a)
      expect(raw(a)).to eq(0b1_0000_0100)
    end

    it 'treats NULL as zero' do
      plant(a, nil)
      CharUser.add_roles!(:author, records: a)
      expect(raw(a)).to eq(0b100)
      plant(b, nil)
      CharUser.remove_roles!(:author, records: b)
      expect(raw(b)).to eq(0)
    end

    it 'is a no-op for empty records, no values or only unknown values' do
      expect(CharUser.add_roles!(:admin, records: [])).to be_nil
      expect(CharUser.add_roles!(records: a)).to be_nil
      expect(CharUser.add_roles!(:bogus, records: a)).to be_nil
      expect(CharUser.remove_roles!(:bogus, records: a)).to be_nil
      expect(raw(a)).to eq(1)
    end

    it 'requires the records: keyword' do
      expect { CharUser.add_roles!(:admin) }.to raise_error(ArgumentError, /records/)
    end

    it 'ignores unknown values but applies the known ones' do
      CharUser.add_roles!(:bogus, :author, records: a)
      expect(raw(a)).to eq(0b101)
    end
  end

  describe 'instance-level atomic methods' do
    let(:record) { CharUser.create!(roles: [:admin]) }

    it 'adds and removes atomically and updates the in-memory attribute' do
      record.add_role!(:author)
      expect(record.roles).to eq(%i[admin author])
      expect(raw(record)).to eq(0b101)
      record.remove_role!(:admin)
      expect(record.roles).to eq([:author])
      expect(raw(record)).to eq(0b100)
    end

    it 'exposes the plural alias' do
      record.add_roles!(:subscriber)
      expect(record.roles).to eq(%i[admin subscriber])
      record.remove_roles!(:subscriber)
      expect(record.roles).to eq([:admin])
    end

    it 'accepts several values at once' do
      record.add_role!(:author, :subscriber)
      expect(record.roles).to eq(%i[admin author subscriber])
    end

    it 'does not leave the record dirty' do
      record.add_role!(:author)
      expect(record.changed?).to be(false)
    end

    it 'sees concurrent database changes (re-reads under lock)' do
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = 10 WHERE id = #{record.id}")
      record.add_role!(:author)
      expect(record.roles).to eq(%i[_legacy author subscriber].sort_by { |r| CharUser.bitwise_schema(:roles)[r] })
      expect(raw(record)).to eq(0b1110)
    end

    it 'preserves ghost bits in memory-independent fashion' do
      plant(record, 0b1_0000_0001)
      record.add_role!(:author)
      record.update!(roles: record.roles + [:subscriber])
      expect(raw(record)).to eq(0b1_0000_1101)
    end

    it 'raises ActiveRecordError on a new record with an exact message' do
      expect { CharUser.new.add_role!(:admin) }.to raise_error(
        ActiveRecord::ActiveRecordError,
        'cannot atomically add roles on a new record; save the record first'
      )
      expect { CharUser.new.remove_role!(:admin) }.to raise_error(
        ActiveRecord::ActiveRecordError,
        'cannot atomically remove roles on a new record; save the record first'
      )
    end

    it 'defines a single method for singular or uncountable column names' do
      model = anonymous_model('singular_models') { bitwise :status, { active: 0 } }
      record = model.create!(status: [])
      record.add_status!(:active)
      expect(record.status).to eq([:active])
    end
  end

  describe 'dup' do
    it 'copies visible flags into a new, unsaved record' do
      original = CharUser.create!(roles: %i[admin author])
      copy = original.dup
      expect(copy).to be_new_record
      expect(copy.roles).to eq(%i[admin author])
      copy.save!
      expect(raw(copy)).to eq(0b101)
    end

    it 'copies NULL columns as empty arrays' do
      original = CharUser.create!(roles: [:admin])
      plant(original, nil)
      expect(original.dup.roles).to eq([])
    end
  end

  describe 'STI and inheritance' do
    it 'shares the parent definitions and persists through subclasses' do
      child_class = Class.new(CharUser) do
        def self.name = 'CharAdmin'
        def self.sti_name = 'CharAdmin'
      end
      expect(child_class.bitwise_schema(:roles)).to eq(CharUser.bitwise_schema(:roles))
      record = child_class.create!(roles: [:author])
      expect(raw(record)).to eq(4)
    end
  end

  describe BitwiseValidator do
    let(:model) do
      anonymous_model do
        bitwise :roles, { admin: 0 }
        validates :roles, bitwise: true
      end
    end

    it 'is valid for known values, empty arrays and nil' do
      expect(model.new(roles: [:admin])).to be_valid
      expect(model.new(roles: [])).to be_valid
      expect(model.new(roles: nil)).to be_valid
    end

    it 'reports unknown values with the exact default message' do
      record = model.new(roles: [:admin, 'x'])
      expect(record).not_to be_valid
      expect(record.errors[:roles]).to eq(['contains invalid values: x'])
    end

    it 'reports at most three values and counts the rest' do
      record = model.new(roles: %w[a b c d e])
      record.valid?
      expect(record.errors[:roles]).to eq(['contains invalid values: a, b, c (and 2 more)'])
    end

    it 'does not add a suffix for exactly three invalid values' do
      record = model.new(roles: %w[a b c])
      record.valid?
      expect(record.errors[:roles]).to eq(['contains invalid values: a, b, c'])
    end

    it 'truncates long values to 64 characters with an ellipsis' do
      record = model.new(roles: ['z' * 65])
      record.valid?
      expect(record.errors[:roles]).to eq(["contains invalid values: #{'z' * 64}…"])
    end

    it 'does not truncate a value of exactly 64 characters' do
      record = model.new(roles: ['z' * 64])
      record.valid?
      expect(record.errors[:roles]).to eq(["contains invalid values: #{'z' * 64}"])
    end

    it 'honors a custom :message' do
      klass = anonymous_model do
        bitwise :roles, { admin: 0 }
        validates :roles, bitwise: { message: 'bad roles' }
      end
      record = klass.new(roles: ['x'])
      record.valid?
      expect(record.errors[:roles]).to eq(['bad roles'])
    end

    it 'exposes its limits as constants' do
      expect(described_class::MAX_REPORTED_VALUES).to eq(3)
      expect(described_class::MAX_REPORTED_LENGTH).to eq(64)
    end

    it 'skips attributes without a bitwise definition' do
      klass = anonymous_model do
        bitwise :roles, { admin: 0 }
        validates :permissions, bitwise: true
      end
      expect(klass.new).to be_valid
    end

    it 'cannot see a rejected value after a save with validate: false' do
      record = model.new(roles: %i[admin nope])
      record.save!(validate: false)
      expect(record.reload.roles).to eq([:admin])
    end
  end

  describe 'constants and version' do
    it 'exposes the documented limits' do
      expect(ActiveRecord::Bitwise::MAX_ARRAY_SIZE).to eq(100)
      expect(ActiveRecord::Bitwise::MAX_BIT_POSITION).to eq(62)
      expect(ActiveRecord::Bitwise::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end

  describe 'multiple columns on one model' do
    it 'keeps columns independent' do
      record = CharUser.create!(roles: [:admin], permissions: [:manage], legacy_roles: [:moderator])
      expect(raw(record)).to eq(1)
      expect(raw(record, :permissions)).to eq(2)
      expect(raw(record, :legacy_roles)).to eq(2)
      expect(record.reload.legacy_roles).to eq([:moderator])
      expect(record.legacy_admin?).to be(false)
      expect(record.admin?).to be(true)
    end

    it 'applies defaults per column on new records' do
      record = CharUser.create!
      expect(raw(record, :permissions)).to eq(1)
      expect(raw(record)).to eq(0)
    end
  end

  describe 'a second table-backed model' do
    it 'works against another table' do
      post = CharPost.create!(external_id: 'x', legacy_flags: [:pinned])
      expect(CharPost.with_legacy_flags(:pinned).pluck(:id)).to eq([post.id])
      post.add_legacy_flag!(:draft)
      expect(post.reload.legacy_flags).to eq(%i[draft pinned])
    end
  end

  describe 'concurrency' do
    it 'never loses updates with concurrent atomic adds' do
      record = CharUser.create!(roles: [])
      threads = %i[admin author subscriber].map do |flag|
        Thread.new do # rubocop:disable ThreadSafety/NewThread
          ActiveRecord::Base.connection_pool.with_connection { CharUser.add_roles!(flag, records: record) }
        end
      end
      threads.each(&:join)
      expect(raw(record)).to eq(0b1101)
    end
  end
end
