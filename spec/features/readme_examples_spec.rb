# typed: false
# frozen_string_literal: true

# One example per claim or code sample in README.md, in README order. If the README changes,
# this file must change with it.
RSpec.describe 'README examples' do
  subject(:user) { user_class.new }

  # The User model of the README "Model Configuration" section.
  let(:user_class) do
    build_model('users', name: 'User') do
      bitwise :roles, { admin: 0, _deprecated_role_1: 1, author: 2, subscriber: 3 }
      bitwise :permissions, { read: 0, manage: 1 }, default: [:read]
      bitwise :legacy_roles, %i[admin moderator author subscriber], prefix: :legacy
      validates :roles, bitwise: true
    end
  end

  describe 'Model Configuration' do
    it 'treats hash values as bit positions: admin is bit 0 (value 1)' do
      expect(raw_value(user_class.create!(roles: [:admin]))).to eq(1)
    end

    it 'treats hash values as bit positions: author is bit 2 (value 4)' do
      expect(raw_value(user_class.create!(roles: [:author]))).to eq(4)
    end

    it 'applies defaults to new records' do
      expect(user.permissions).to eq([:read])
    end

    it 'never resurrects defaults for persisted NULL rows' do
      persisted = plant_raw_value(user_class.create!, nil, :permissions)

      expect(persisted.permissions).to eq([])
    end

    it 'maps an Array mapping index to the bit offset' do
      expect(raw_value(user_class.create!(legacy_roles: %i[admin author]), :legacy_roles)).to eq(0b101)
    end

    it 'prefixes the methods of the legacy_roles column' do
      expect(user).to respond_to(:legacy_admin?, :legacy_moderator?)
    end

    # The README lists what raises ConfigurationError at definition time.
    [
      ['a non-integer bit position', { a: 'one' }],
      ['a negative bit position', { a: -1 }],
      ['a bit position above 62', { a: 63 }],
      ['two keys with the same bit position', { a: 1, b: 1 }]
    ].each do |label, mapping|
      it "raises ConfigurationError for #{label}" do
        expect { build_model { bitwise :roles, mapping } }.to raise_error(ActiveRecord::Bitwise::ConfigurationError)
      end
    end

    it 'raises ConfigurationError for duplicate keys' do
      expect { build_model { bitwise :roles, %i[a a] } }.to raise_error(ActiveRecord::Bitwise::ConfigurationError)
    end

    it 'raises ConfigurationError for defaults that are not in the mapping' do
      expect { build_model { bitwise :roles, { a: 0 }, default: [:b] } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError)
    end

    it 'raises ConfigurationError for accessors that would shadow a database column' do
      expect { build_model { bitwise :roles, { permissions: 0 } } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError)
    end

    it 'raises ConfigurationError for accessors that collide with another bitwise column' do
      expect { build_model { bitwise(:roles, { admin: 0 }) && bitwise(:legacy_roles, { admin: 0 }) } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError)
    end

    it 'is an ArgumentError, so existing rescue clauses keep working' do
      expect(ActiveRecord::Bitwise::ConfigurationError.superclass).to eq(ArgumentError)
    end
  end

  describe 'Database Migration: capacity' do
    it 'accepts 7 flags on a 1-byte column when the database keeps the size' do
      narrow = build_model('capacity_records') { bitwise :tiny, { a: 0, g: 6 } }

      expect { narrow.new }.not_to raise_error
    end

    it 'accepts 31 flags on a 4-byte column' do
      regular = build_model('capacity_records') { bitwise :regular, { a: 0, last: 30 } }

      expect { regular.new }.not_to raise_error
    end

    it 'accepts 63 flags on an 8-byte column' do
      wide = build_model('capacity_records') { bitwise :big, { a: 0, last: 62 } }

      expect { wide.new }.not_to raise_error
    end

    it 'raises ArgumentError when a bit position does not fit the column' do
      overflow = build_model('capacity_records') { bitwise :regular, { a: 31 } }

      expect { overflow.new }.to raise_error(ArgumentError, /max 31 flags/)
    end
  end

  describe 'Prefix and Suffix Options' do
    let(:model) do
      build_model do
        bitwise :roles, { admin: 0, author: 1 }, suffix: true
        bitwise :permissions, { admin: 0, author: 1 }, prefix: :can
      end
    end

    it 'uses the roles column for admin_role?' do
      record = model.new
      record.roles = [:admin]

      expect(record.admin_role?).to be(true)
    end

    it 'uses the permissions column for can_admin?' do
      record = model.new
      record.permissions = [:admin]

      expect(record.can_admin?).to be(true)
    end

    it 'keeps the two columns separate' do
      record = model.new
      record.permissions = [:admin]

      expect(record.admin_role?).to be(false)
    end
  end

  describe 'Active Record Operations' do
    it 'sets roles using an array of Symbols' do
      user.roles = %i[admin author]

      expect(user.roles).to eq(%i[admin author])
    end

    it 'sets roles using Strings' do
      user.roles = ['subscriber']

      expect(user.roles).to eq([:subscriber])
    end

    it 'clears all values with an empty array' do
      user.roles = []

      expect(user.roles).to eq([])
    end

    it 'preserves unmapped bits through the setter' do
      stored = plant_raw_value(user_class.create!, 0b1_0000)
      stored.update!(roles: [:admin])

      expect(raw_value(stored)).to eq(0b1_0001)
    end

    it 'preserves unmapped bits through write_attribute' do
      stored = plant_raw_value(user_class.create!, 0b1_0000)
      stored.tap { |record| record.write_attribute(:roles, [:admin]) }.save!

      expect(raw_value(stored)).to eq(0b1_0001)
    end

    it 'preserves unmapped bits through []=' do
      stored = plant_raw_value(user_class.create!, 0b1_0000)
      stored.tap { |record| record[:roles] = [:admin] }.save!

      expect(raw_value(stored)).to eq(0b1_0001)
    end

    it 'preserves unmapped bits through update_column' do
      stored = plant_raw_value(user_class.create!, 0b1_0000)
      stored.update_column(:roles, [:admin])

      expect(raw_value(stored)).to eq(0b1_0001)
    end

    it 'preserves unmapped bits through update_all' do
      stored = plant_raw_value(user_class.create!, 0b1_0000)
      user_class.update_all(roles: [:admin])

      expect(raw_value(stored)).to eq(0b1_0001)
    end

    it 'overwrites the raw bitmask verbatim when assigning an Integer' do
      stored = user_class.create!
      stored.update!(roles: 0b11_0001)

      expect(raw_value(stored)).to eq(0b11_0001)
    end

    it 'clears unmapped bits when assigning 0' do
      stored = plant_raw_value(user_class.create!, 0b1_0001)
      stored.update!(roles: 0)

      expect(raw_value(stored)).to eq(0)
    end

    it 'clears unmapped bits when assigning nil' do
      stored = plant_raw_value(user_class.create!, 0b1_0001)
      stored.update!(roles: nil)

      expect(raw_value(stored)).to be_nil
    end
  end

  describe 'Form Helpers & Strong Parameters' do
    it 'ignores the empty string a checkbox form submits' do
      user.roles = ['', 'admin', 'author']

      expect(user.roles).to eq(%i[admin author])
    end

    it 'ignores nil entries' do
      user.roles = [nil, 'admin']

      expect(user.roles).to eq([:admin])
    end
  end

  describe 'Dirty Tracking' do
    let(:persisted) { user_class.create! }

    it 'reports the virtual array attribute as changed' do
      persisted.roles = [:admin]

      expect(persisted.roles_changed?).to be(true)
    end

    it 'exposes the previous value with roles_was' do
      persisted.roles = [:admin]

      expect(persisted.roles_was).to eq([])
    end
  end

  describe 'Boolean Setters and Getters' do
    it 'answers false to the question methods of an empty record' do
      expect([user.admin?, user.author?]).to eq([false, false])
    end

    it 'sets flags with the boolean setters' do
      user.admin = true
      user.author = true

      expect(user.roles).to eq(%i[admin author])
    end

    it 'saves instantly with the bang method' do
      user.admin = true
      user.author = true
      user.admin!

      expect(user).to be_persisted
    end

    it 'stores 5 (1 + 4) for admin and author' do
      user.admin = true
      user.author = true
      user.admin!

      expect(user.reload.roles_before_type_cast).to eq(5)
    end

    ['0', 'false', '', 'off', 0, false, nil].each do |falsy|
      it "disables the flag when assigned #{falsy.inspect}" do
        user.roles = [:admin]
        user.admin = falsy

        expect(user.admin?).to be(false)
      end
    end
  end

  describe 'High Concurrency (SQL Atomic Methods)' do
    let!(:record) { user_class.create!(roles: [:author]) }

    it 'adds a role with a class-level atomic UPDATE' do
      user_class.add_roles!(:admin, records: record.id)

      expect(raw_value(record)).to eq(0b101)
    end

    it 'issues the documented OR statement' do
      column = user_class.connection.quote_column_name('roles')
      statements = capture_sql { user_class.add_roles!(:admin, records: record.id) }

      expect(statements).to include(a_string_including("#{column} = COALESCE(#{column}, 0) | 1"))
    end

    it 'removes a role with the instance-level atomic method' do
      record.remove_role!(:author)

      expect(raw_value(record)).to eq(0)
    end

    it 'issues the documented subtraction statement' do
      column = user_class.connection.quote_column_name('roles')
      expected = "#{column} = COALESCE(#{column}, 0) - (COALESCE(#{column}, 0) & 4)"
      statements = capture_sql { record.remove_role!(:author) }

      expect(statements).to include(a_string_including(expected))
    end

    it 'refreshes the in-memory attribute from the database' do
      record.add_role!(:admin)

      expect(record.roles).to eq(%i[admin author])
    end

    it 'raises ActiveRecordError for a new record' do
      expect { user.add_role!(:admin) }.to raise_error(ActiveRecord::ActiveRecordError, /new record/)
    end

    it 'generates only add_status!/remove_status! for the already singular column :status' do
      singular = build_model('singular_models') { bitwise :status, { active: 0 } }

      expect(singular.new).not_to respond_to(:add_statuses!)
    end

    it 'keeps the applied value in memory when an enclosing transaction is rolled back' do
      user_class.transaction do
        record.add_role!(:admin)
        raise ActiveRecord::Rollback
      end

      expect(record.roles).to eq(%i[admin author])
    end

    it 'is re-synchronized by reload after such a rollback' do
      user_class.transaction do
        record.add_role!(:admin)
        raise ActiveRecord::Rollback
      end

      expect(record.reload.roles).to eq([:author])
    end
  end

  describe 'Scopes (Querying the Database)' do
    let!(:admin) { user_class.create!(roles: [:admin]) }
    let!(:author) { user_class.create!(roles: [:author]) }
    let!(:both) { user_class.create!(roles: %i[admin author]) }
    let!(:subscriber) { user_class.create!(roles: [:subscriber]) }

    it 'finds all users that have the :admin role' do
      expect(user_class.with_roles(:admin)).to contain_exactly(admin, both)
    end

    it 'finds all users that have both :admin and :author' do
      expect(user_class.with_roles(:admin, :author)).to contain_exactly(both)
    end

    it 'finds all users that have either :admin or :author' do
      expect(user_class.with_any_roles(:admin, :author)).to contain_exactly(admin, author, both)
    end

    it 'finds users who are only admins' do
      expect(user_class.with_exact_roles(:admin)).to contain_exactly(admin)
    end

    it 'finds all users that do not have the :author role' do
      expect(user_class.without_roles(:author)).to contain_exactly(admin, subscriber)
    end

    it 'qualifies columns so scopes stay valid under joins' do
      joined = user_class.joins('INNER JOIN users AS other ON other.id = users.id').with_roles(:admin)

      expect(joined).to contain_exactly(admin, both)
    end
  end

  describe 'Hash Conditions (where, find_by)' do
    let!(:admin) { user_class.create!(roles: [:admin]) }
    let!(:both) { user_class.create!(roles: %i[admin author]) }
    let(:column) { qualified_column(user_class) }

    it 'matches exactly admin with where(roles: [:admin])' do
      expect(user_class.where(roles: [:admin])).to contain_exactly(admin)
    end

    it 'queries WHERE roles = 1 for where(roles: [:admin])' do
      expect(user_class.where(roles: [:admin]).to_sql).to include("#{column} = 1")
    end

    it 'queries WHERE roles != 1 for where.not(roles: [:admin])' do
      expect(user_class.where.not(roles: [:admin]).to_sql).to include("#{column} != 1")
    end

    it 'finds the exact bitmask 5 with find_by(roles: %i[admin author])' do
      expect(user_class.find_by(roles: %i[admin author])).to eq(both)
    end

    it 'queries roles = 5 for find_by(roles: %i[admin author])' do
      expect(user_class.where(roles: %i[admin author]).to_sql).to include("#{column} = 5")
    end

    it 'passes raw integers through untouched' do
      expect(user_class.where(roles: 5)).to contain_exactly(both)
    end

    it 'raises UnknownValueError for unknown flag values' do
      expect { user_class.where(roles: [:typo]) }.to raise_error(ActiveRecord::Bitwise::UnknownValueError)
    end
  end

  describe 'Graceful Validation (Safe Assignment)' do
    it 'flags invalid values instead of raising on assignment' do
      user.roles = %i[admin hacker]

      expect(user.valid?).to be(false)
    end

    it 'reports the invalid value in the error message' do
      user.roles = %i[admin hacker]
      user.valid?

      expect(user.errors[:roles]).to eq(['contains invalid values: hacker'])
    end

    it 'supports the :message option' do
      custom = build_model { bitwise(:roles, { admin: 0 }) && validates(:roles, bitwise: { message: 'is wrong' }) }
      record = custom.new(roles: [:nope])
      record.valid?

      expect(record.errors[:roles]).to eq(['is wrong'])
    end

    it 'truncates reflected values to the first 3, 64 characters each' do
      user.roles = ['a' * 70, 'b', 'c', 'd']
      user.valid?

      expect(user.errors[:roles]).to eq(["contains invalid values: #{'a' * 64}…, b, c (and 1 more)"])
    end

    it 'drops the invalid value and persists the valid subset when saving without validation' do
      user.roles = %i[admin hacker]
      user.save(validate: false)

      expect(raw_value(user)).to eq(1)
    end

    it 'raises UnknownValueError from update_all instead of zeroing the column' do
      existing = user_class.create!(roles: [:admin])
      capture_error { user_class.update_all(roles: [:hacker]) }

      expect(raw_value(existing)).to eq(1)
    end
  end

  describe 'Known Limitations' do
    it 'rejects bit positions above 62 at definition time (1. the 63-bit limit)' do
      expect { build_model { bitwise :roles, { a: 63 } } }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /invalid bit position 63/)
    end

    it 'lets a re-used bit position reveal old data as the new flag (2. ghost bit refactoring)' do
      stored = plant_raw_value(user_class.create!, 0b10)
      editor_release = build_model { bitwise :roles, { admin: 0, editor: 1 } }

      expect(editor_release.find(stored.id).roles).to eq([:editor])
    end

    it 'caps assigned arrays at 100 elements (3. array RAM exhaustion)' do
      expect { user.roles = Array.new(101) { |i| "role_#{i}" } }
        .to raise_error(ArgumentError, 'Array size cannot exceed 100')
    end

    it 'gives every class its own configuration (8. STI column sharing)' do
      child = build_model(parent: user_class, name: 'Customer')

      expect(child.bitwise_definitions[:roles]).not_to equal(user_class.bitwise_definitions[:roles])
    end

    it 'exposes the raw integer without allocating arrays (9. allocation overhead)' do
      stored = user_class.create!(roles: %i[admin author])

      expect(user_class.find(stored.id).roles_before_type_cast).to eq(5)
    end

    it 'exposes the schema for decoding the integer (10. opaque raw data)' do
      expect(user_class.bitwise_schema(:legacy_roles)).to eq(admin: 0, moderator: 1, author: 2, subscriber: 3)
    end

    it 'raises FrozenError on user.roles << :admin (14. the << trap)' do
      expect { user.roles << :admin }.to raise_error(FrozenError)
    end

    it 'supports reassignment with user.roles += [:admin] (14. the << trap)' do
      user.roles += [:admin]

      expect(user.roles).to eq([:admin])
    end

    it 'coerces raw values that an adapter returns as Strings (16. adapter differences)' do
      adapter_row = { id: 1, roles: '5' }.transform_keys(&:to_s)

      expect(user_class.instantiate(adapter_row).roles).to eq(%i[admin author])
    end
  end
end
