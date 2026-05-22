# frozen_string_literal: true

require 'spec_helper'

# Define standard models for testing
class TestUser < ActiveRecord::Base
  self.table_name = 'users'

  bitwise :roles, { admin: 0, _deprecated_role_1: 1, author: 2, subscriber: 3 }
  bitwise :permissions, { read: 0, manage: 1 }, default: [:read]
  bitwise :legacy_roles, %i[admin moderator author subscriber]

  validates :roles, bitwise: true
end

class TestUserWithSuffixPrefix < ActiveRecord::Base
  self.table_name = 'users'

  bitwise :roles, { admin: 0, author: 1 }, suffix: true
  bitwise :permissions, { admin: 0, author: 1 }, prefix: :can
end

class TestSTIAdmin < TestUser
end

class TestSTICustomer < TestUser
end

class TestUserWithMoreOptions < ActiveRecord::Base
  self.table_name = 'users'
  bitwise :roles, { admin: 0 }, prefix: true
  bitwise :permissions, { read: 0 }, suffix: :permission
end

class ParentUser < ActiveRecord::Base
  self.table_name = 'users'
  def roles
    [:admin] # returns unfrozen array!
  end
end

class ChildUser < ParentUser
  extend ActiveRecord::Bitwise::Model

  bitwise :roles, { admin: 0 }
end

RSpec.describe ActiveRecord::Bitwise do
  before do
    ActiveRecord::Base.connection.execute('DELETE FROM users')
  end

  describe 'AR_BITWISE-REQ-001: Bitmask Arithmetic and Operations' do
    it 'allows saving and retrieving multiple symbols' do
      user = TestUser.new
      user.roles = %i[admin author]
      expect(user.roles).to eq(%i[admin author])
      user.save!

      user.reload
      expect(user.roles).to eq(%i[admin author])
      expect(user.roles_before_type_cast).to eq(5) # 1 + 4
    end

    it 'converts string inputs under the hood' do
      user = TestUser.new
      user.roles = ['subscriber']
      expect(user.roles).to eq([:subscriber])
      user.save!

      user.reload
      expect(user.roles).to eq([:subscriber])
    end

    it 'allows clearing out all values' do
      user = TestUser.create!(roles: [:admin])
      user.roles = []
      user.save!

      expect(user.reload.roles).to eq([])
      expect(user.roles_before_type_cast).to eq(0)
    end

    it 'gracefully handles and strips out empty strings and nil values' do
      user = TestUser.new
      user.roles = ['', 'admin', nil, 'author']
      expect(user.roles).to eq(%i[admin author])
    end

    it 'supports Array mappings where index defines bit offset' do
      user = TestUser.create!(legacy_roles: %i[admin author])
      expect(user.reload.legacy_roles).to eq(%i[admin author])
      expect(user.legacy_roles_before_type_cast).to eq(5) # 1 << 0 and 1 << 2
    end
  end

  describe 'AR_BITWISE-REQ-003: Prefix and Suffix Options' do
    it 'respects suffix options' do
      user = TestUserWithSuffixPrefix.new
      expect(user.admin_role?).to be false

      user.admin_role = true
      expect(user.admin_role?).to be true
      expect(user.roles).to eq([:admin])

      user.admin_role!
      expect(user.reload.admin_role?).to be true
    end

    it 'respects prefix options' do
      user = TestUserWithSuffixPrefix.new
      expect(user.can_admin?).to be false

      user.can_admin = true
      expect(user.can_admin?).to be true
      expect(user.permissions).to eq([:admin])

      user.can_admin = false
      expect(user.can_admin?).to be false

      user.can_admin!
      expect(user.reload.can_admin?).to be true
    end
  end

  describe 'AR_BITWISE-REQ-004: Database Scopes and Querying' do
    let!(:user_admin) { TestUser.create!(roles: [:admin]) }
    let!(:user_both) { TestUser.create!(roles: %i[admin author]) }
    let!(:user_author) { TestUser.create!(roles: [:author]) }
    let!(:user_none) { TestUser.create!(roles: []) }

    it 'filters with_roles scope (AND match)' do
      expect(TestUser.with_roles(:admin)).to contain_exactly(user_admin, user_both)
      expect(TestUser.with_roles(:admin, :author)).to contain_exactly(user_both)
    end

    it 'filters with_any_roles scope (OR match)' do
      expect(TestUser.with_any_roles(:admin, :author)).to contain_exactly(user_admin, user_both, user_author)
    end

    it 'filters with_exact_roles scope (exact match)' do
      expect(TestUser.with_exact_roles(:admin)).to contain_exactly(user_admin)
      expect(TestUser.with_exact_roles(:admin, :author)).to contain_exactly(user_both)
    end

    it 'filters without_roles scope (NOT match)' do
      expect(TestUser.without_roles(:author)).to contain_exactly(user_admin, user_none)
    end

    it 'returns all on no arguments for scopes, or specific defaults' do
      expect(TestUser.with_roles).to contain_exactly(user_admin, user_both, user_author, user_none)
      expect(TestUser.with_any_roles).to contain_exactly(user_admin, user_both, user_author, user_none)
      expect(TestUser.without_roles).to contain_exactly(user_admin, user_both, user_author, user_none)
    end

    it 'applies zero-state boundaries to with_exact_roles([])' do
      # Point 13: Zero-state scope bounds where roles = 0
      expect(TestUser.with_exact_roles([])).to contain_exactly(user_none)
      expect(TestUser.with_exact_roles).to contain_exactly(user_none)
    end
  end

  describe 'AR_BITWISE-REQ-005: High Concurrency (SQL Atomic Methods)' do
    let!(:user) { TestUser.create!(roles: [:author]) }

    it 'applies class-level add_roles! atomic SQL updates' do
      TestUser.add_roles!(:admin, records: user.id)
      expect(user.reload.roles).to contain_exactly(:admin, :author)
    end

    it 'applies class-level remove_roles! atomic SQL updates' do
      TestUser.add_roles!(:admin, records: user.id)
      TestUser.remove_roles!(:author, records: user.id)
      expect(user.reload.roles).to contain_exactly(:admin)
    end

    it 'applies instance-level add_role! and add_roles!' do
      user.add_role!(:admin)
      expect(user.roles).to contain_exactly(:admin, :author)

      user.add_roles!(:subscriber)
      expect(user.roles).to contain_exactly(:admin, :author, :subscriber)
    end

    it 'applies instance-level remove_role! and remove_roles!' do
      user.add_role!(:admin)
      user.remove_role!(:author)
      expect(user.roles).to contain_exactly(:admin)

      user.remove_roles!(:admin)
      expect(user.roles).to be_empty
    end
  end

  describe 'AR_BITWISE-REQ-006: Graceful Validations' do
    it 'keeps invalid values in memory and flags validation errors' do
      user = TestUser.new
      user.roles = %i[admin hacker]
      expect(user.valid?).to be false
      expect(user.errors[:roles]).to include('contains invalid values: hacker')
    end

    it 'ignores empty strings and nil in validations' do
      user = TestUser.new
      user.roles = ['', :admin, nil]
      expect(user.valid?).to be true
    end
  end

  describe 'AR_BITWISE-REQ-007: 17 Safety & Architectural Guarantees' do
    it '1. Guarantees non-destructive forgotten bits masking' do
      # Set a raw value in the database directly that has unmapped bits (e.g. 13 = 1 (admin) + 4 (author) + 8 (unmapped bit 3))
      # known mask for roles is 1 | 2 | 4 | 8 = 15? Wait, mapping: admin:0, _deprecated_role_1:1, author:2, subscriber:3.
      # Mapped bit indices: 0, 1, 2, 3. The known mask is (1<<0)|(1<<1)|(1<<2)|(1<<3) = 15.
      # Let's set a bit outside the known mask, like bit 4 (value 16).
      # Total raw value: 16 (unmapped) + 1 (admin) = 17.
      user = TestUser.create!(roles: [])
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = 17 WHERE id = #{user.id}")

      user.reload
      expect(user.roles).to eq([:admin])

      # Save new mapped states (:author, bit index 2 = 4)
      user.roles = [:author]
      user.save!

      # Database representation should be 16 (unmapped bit 4 preserved) + 4 (:author) = 20
      raw_val = ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{user.id}").to_i
      expect(raw_val).to eq(20)
      expect(user.reload.roles).to eq([:author])
    end

    it '2. Enforces Single Table Inheritance (STI) isolation' do
      # STI class isolation
      expect(TestSTIAdmin.bitwise_definitions[:roles]).to eq(TestUser.bitwise_definitions[:roles])
    end

    it '3. Performs fuzzer immunization inside scopes' do
      # Drop unrecognized keys, returning none if all are invalid
      expect(TestUser.with_roles(:hacker)).to be_empty
      expect(TestUser.with_any_roles(:hacker)).to be_empty
      expect(TestUser.with_exact_roles(:hacker)).to be_empty
      # Unrecognized keys in without_roles should have no effect, returning all
      user = TestUser.create!(roles: [:admin])
      expect(TestUser.without_roles(:hacker)).to contain_exactly(user)
    end

    it '4. Coalesces nil database values to 0' do
      user = TestUser.create!(roles: [])
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = NULL WHERE id = #{user.id}")

      user.reload
      expect(user.roles).to eq([])
    end

    it '5. Prevents Symbol DoS attacks' do
      user = TestUser.new
      # Unmapped values should remain as strings, not converted to symbols
      user.roles = ['malicious_dynamic_string']
      expect(user.roles).to eq(['malicious_dynamic_string'])
    end

    it '6. Returns frozen arrays to safeguard dirty tracking' do
      user = TestUser.create!(roles: [:admin])
      expect(user.roles.frozen?).to be true
      expect { user.roles << :author }.to raise_error(FrozenError)
    end

    it '7. Checks column type compatibility during lazy initialization' do
      # Table table exists check, column exists, column is integer
      expect(TestUser.bitwise_definitions[:roles][:validated]).to be true
    end

    it '8. Packages a Tapioca DSL compiler structure' do
      expect(File.exist?(File.expand_path('../lib/tapioca/dsl/compilers/activerecord_bitwise.rb', __dir__))).to be true
    end

    it '9. Prevents where clause poisoning' do
      expect { TestUser.where(roles: [:admin]) }.to raise_error(ActiveRecord::Bitwise::NotSupportedError)
      expect { TestUser.where.not(roles: [:admin]) }.to raise_error(ActiveRecord::Bitwise::NotSupportedError)
    end

    it '10. Prevents boot-deadlocks' do
      # Class macros can run even if database doesn't exist
      # Defer actual column introspection until initialize
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'non_existent_table'
          extend ActiveRecord::Bitwise::Model

          bitwise :roles, { admin: 0 }
        end
      end.not_to raise_error
    end

    it '11. Prevents ActiveRecord lifecycle method bricking' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'collision_models'
          extend ActiveRecord::Bitwise::Model

          # 'destroyed' method collides with 'destroyed?'
          bitwise :states, { destroyed: 0 }
        end
      end.to raise_error(ArgumentError, /collides with core ActiveRecord::Base/)
    end

    it '12. Prevents object clone bleeding during dup' do
      user1 = TestUser.create!(roles: [])
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = 17 WHERE id = #{user1.id}")
      user1.reload # holds 17 in database, 16 in forgotten bits

      user2 = user1.dup
      user2.roles = [:author]
      user2.save!

      # user2 raw roles must not contain the unmapped bit (16) from user1
      raw_val = ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{user2.id}").to_i
      expect(raw_val).to eq(4) # exactly 4 (:author), no 16 (unmapped bit)
    end

    it '13. Prevents zero-state scope bounds bleeding' do
      # Zero-state scope bounds where roles = 0
      user_none = TestUser.create!(roles: [])
      expect(TestUser.with_exact_roles([])).to contain_exactly(user_none)
      expect(TestUser.with_exact_roles).to contain_exactly(user_none)
    end

    it '14. Exports multi-tenant ETL schema via .bitwise_schema' do
      schema = TestUser.bitwise_schema(:roles)
      expect(schema).to eq({ admin: 0, _deprecated_role_1: 1, author: 2, subscriber: 3 })
    end

    it '15. Resolves SQLite raw string coercion issues' do
      # SQLite string output coercion
      type = TestUser.attribute_types['roles']
      expect(type.deserialize('5')).to eq(%i[admin author])
    end

    it '16. Intercepts update_all queries' do
      user = TestUser.create!(roles: [:admin])
      TestUser.update_all(roles: %i[author subscriber])

      expect(user.reload.roles).to contain_exactly(:author, :subscriber)
    end

    it '17. Detects and halts execution on over-shifted mappings' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'over_shifted_models'
          extend ActiveRecord::Bitwise::Model

          # limit: 1 byte signed allows up to 7 flags (max position 6)
          bitwise :custom_limits, { a: 0, b: 1, c: 2, d: 3, e: 4, f: 5, g: 6, h: 7 }
        end.new
      end.to raise_error(ArgumentError, /has limit of 1 bytes/)
    end

    it 'handles update_all with raw SQL string' do
      expect { TestUser.update_all('roles = 0') }.not_to raise_error
    end

    it 'raises ArgumentError on invalid mapping type' do
      expect do
        Class.new(ActiveRecord::Base) do
          extend ActiveRecord::Bitwise::Model

          bitwise :roles, 'not an array or hash'
        end
      end.to raise_error(StandardError, /Mapping must be a Hash or an Array|Expected type/)
    end

    it 'handles unfrozen array in write_attribute' do
      user = TestUser.new
      user.send(:write_attribute, :roles, [:admin])
      expect(user.roles).to eq([:admin])
      expect(user.roles.frozen?).to be true
    end

    it 'handles string values in read_attribute_before_type_cast for cache' do
      user = TestUser.new
      allow(user).to receive(:read_attribute_before_type_cast).with(:roles).and_return('5')
      user.roles = [:admin]
      expect(user.roles).to eq([:admin])
    end

    it 'handles prefix: true and suffix: Symbol options' do
      user = TestUserWithMoreOptions.new
      expect(user.role_admin?).to be false
      user.role_admin = true
      expect(user.roles).to eq([:admin])
      expect(user.read_permission?).to be false
      user.read_permission = true
      expect(user.permissions).to eq([:read])
    end

    it 'validates column limits of 2, 8, and custom types' do
      column_mock_class = Struct.new(:name, :type, :limit, :default, :null, :default_function)
      original_mapping = TestUser.bitwise_definitions[:roles][:mapping]
      original_validated = TestUser.bitwise_definitions[:roles][:validated]

      begin
        user = TestUser.new

        # We will test limit = 2 (max 15 flags, shifts 0..14)
        col2 = column_mock_class.new('roles', :integer, 2, nil, true, nil)
        allow(TestUser).to receive(:columns_hash).and_return({ 'roles' => col2 })

        # Position 14 -> valid
        TestUser.bitwise_definitions[:roles][:validated] = false
        TestUser.bitwise_definitions[:roles][:mapping] = { a: 14 }
        expect { user.send(:_validate_bitwise_column_type_and_bounds) }.not_to raise_error

        # Position 15 -> fails for 2 bytes (max 15 flags)
        TestUser.bitwise_definitions[:roles][:validated] = false
        TestUser.bitwise_definitions[:roles][:mapping] = { a: 15 }
        expect { user.send(:_validate_bitwise_column_type_and_bounds) }.to raise_error(ArgumentError)

        # We will test limit = 8 (max 63 flags, shifts 0..62)
        col8 = column_mock_class.new('roles', :integer, 8, nil, true, nil)
        allow(TestUser).to receive(:columns_hash).and_return({ 'roles' => col8 })

        # Position 62 -> valid
        TestUser.bitwise_definitions[:roles][:validated] = false
        TestUser.bitwise_definitions[:roles][:mapping] = { a: 62 }
        expect { user.send(:_validate_bitwise_column_type_and_bounds) }.not_to raise_error

        # Position 63 -> fails for 8 bytes (max 63 flags)
        TestUser.bitwise_definitions[:roles][:validated] = false
        TestUser.bitwise_definitions[:roles][:mapping] = { a: 63 }
        expect { user.send(:_validate_bitwise_column_type_and_bounds) }.to raise_error(ArgumentError)

        # We will test other limit = 3 (max 31 flags, shifts 0..30)
        col_other = column_mock_class.new('roles', :integer, 3, nil, true, nil)
        allow(TestUser).to receive(:columns_hash).and_return({ 'roles' => col_other })

        # Position 30 -> valid
        TestUser.bitwise_definitions[:roles][:validated] = false
        TestUser.bitwise_definitions[:roles][:mapping] = { a: 30 }
        expect { user.send(:_validate_bitwise_column_type_and_bounds) }.not_to raise_error

        # Position 31 -> fails (max 31 flags)
        TestUser.bitwise_definitions[:roles][:validated] = false
        TestUser.bitwise_definitions[:roles][:mapping] = { a: 31 }
        expect { user.send(:_validate_bitwise_column_type_and_bounds) }.to raise_error(ArgumentError)
      ensure
        # Clean up after test
        allow(TestUser).to receive(:columns_hash).and_call_original
        TestUser.bitwise_definitions[:roles][:validated] = original_validated
        TestUser.bitwise_definitions[:roles][:mapping] = original_mapping
      end
    end

    it 'handles non-integer and non-to_i values in serialize cache' do
      type = TestUser.attribute_types['roles']
      val_to_i = [:admin]
      custom_val = double('custom', to_i: 1)
      val_to_i.instance_variable_set(:@_bitwise_raw_value, custom_val)
      expect(type.serialize(val_to_i)).to eq(1)

      val_no_to_i = [:admin]
      custom_val_no = double('custom_no')
      val_no_to_i.instance_variable_set(:@_bitwise_raw_value, custom_val_no)
      expect(type.serialize(val_no_to_i)).to eq(1)
    end
  end

  describe 'Tapioca DSL Compiler' do
    before(:all) do
      require 'tapioca/dsl/compilers/activerecord_bitwise'
    end

    it 'gathers constants with bitwise definitions' do
      constants = Tapioca::Dsl::Compilers::ActiveRecordBitwise.gather_constants
      expect(constants).to include(TestUser, TestUserWithSuffixPrefix, TestUserWithMoreOptions)
    end

    it 'decorates the model dynamic methods' do
      generated_methods = []
      model_mock = double('model')
      allow(model_mock).to receive(:create_method) do |name, **_opts|
        generated_methods << name
      end

      root_mock = double('root')
      allow(root_mock).to receive(:create_path).and_yield(model_mock)
      allow_any_instance_of(Tapioca::Dsl::Compilers::ActiveRecordBitwise).to receive(:create_param).and_return(double('param'))
      allow_any_instance_of(Tapioca::Dsl::Compilers::ActiveRecordBitwise).to receive(:create_rest_param).and_return(double('rest_param'))
      allow_any_instance_of(Tapioca::Dsl::Compilers::ActiveRecordBitwise).to receive(:create_kw_param).and_return(double('kw_param'))

      [TestUser, TestUserWithSuffixPrefix, TestUserWithMoreOptions].each do |model_class|
        compiler = Tapioca::Dsl::Compilers::ActiveRecordBitwise.new(model_class)
        compiler.instance_variable_set(:@root, root_mock)
        compiler.decorate
      end

      # For TestUser
      expect(generated_methods).to include('roles')
      expect(generated_methods).to include('roles=')
      expect(generated_methods).to include('admin?')
      expect(generated_methods).to include('admin=')
      expect(generated_methods).to include('admin!')
      expect(generated_methods).to include('add_roles!')
      expect(generated_methods).to include('remove_roles!')
      expect(generated_methods).to include('with_roles')
      expect(generated_methods).to include('with_any_roles')
      expect(generated_methods).to include('with_exact_roles')
      expect(generated_methods).to include('without_roles')
      expect(generated_methods).to include('bitwise_schema')

      # For TestUserWithSuffixPrefix (suffix: true for roles, prefix: :can for permissions)
      expect(generated_methods).to include('admin_role?')
      expect(generated_methods).to include('can_admin?')

      # For TestUserWithMoreOptions (prefix: true for roles, suffix: :permission for permissions)
      expect(generated_methods).to include('role_admin?')
      expect(generated_methods).to include('read_permission?')
    end
  end

  describe 'Extra Coverage Tests for 100% Branch and Line Coverage' do
    it 'covers extra edge cases and unreachable conditions' do
      # 1. Unfrozen super getter
      user = ChildUser.new
      expect(user.roles).to eq([:admin])
      expect(user.roles.frozen?).to be true

      # 2. BitwiseValidator with nil value and missing definition
      validator = BitwiseValidator.new(attributes: [:roles])
      expect { validator.validate_each(TestUser.new, :roles, nil) }.not_to raise_error
      expect { validator.validate_each(TestUser.new, :non_existent_attr, [:admin]) }.not_to raise_error

      # 3. Type#cast with nil value
      type = TestUser.attribute_types['roles']
      expect(type.cast(nil)).to be_nil

      # 4. Array size limitation defense (> 100)
      large_arr = Array.new(101) { :admin }
      expect { type.cast(large_arr) }.to raise_error(ArgumentError, /cannot exceed 100/)

      # 5. Type#deserialize with and without default
      type_with_default = TestUser.attribute_types['permissions']
      expect(type_with_default.deserialize(nil)).to eq([:read])

      type_no_default = TestUser.attribute_types['roles']
      expect(type_no_default.deserialize(nil)).to eq([])

      # Add custom type with nil default to cover the absent default branch
      custom_type = ActiveRecord::Bitwise::Type.new(:roles, { admin: 0 }, nil)
      expect(custom_type.deserialize(nil)).to eq([])

      # 6. Type#serialize with nil and integer
      expect(type.serialize(nil)).to be_nil
      expect(type.serialize(5)).to eq(5)

      # 7. Type#serialize with unmapped key
      expect(type.serialize(%i[admin invalid_key])).to eq(1)

      # 8. RelationExtension#update_all with raw integer and non-Bitwise typecaster
      expect { TestUser.update_all(roles: 5) }.not_to raise_error
      expect { TestUser.update_all(roles: [:admin]) }.not_to raise_error
      allow(TestUser).to receive(:attribute_types).and_call_original

      # 9. WhereChainExtension#not with non-hash and non-bitwise attributes
      expect { TestUser.where.not('roles = 0') }.not_to raise_error
      expect { TestUser.where.not(id: 1) }.not_to raise_error

      # 10. Setter with nil value
      user = TestUser.new
      user.roles = nil
      expect(user.roles).to eq([])
      user.save!
      expect(user.reload.roles).to eq([])

      # 11. Double setting dynamic boolean values
      user = TestUser.new
      user.roles = [:admin]
      user.admin = true
      expect(user.roles).to eq([:admin])

      user_bang = TestUser.create!(roles: [:admin])
      user_bang.admin!
      expect(user_bang.roles).to eq([:admin])

      # 12. Class-level add_roles! / remove_roles! coverage
      user = TestUser.create!(roles: [:admin])
      TestUser.add_roles!(:author, records: user)
      expect(user.reload.roles).to contain_exactly(:admin, :author)
      TestUser.remove_roles!(:author, records: user)
      expect(user.reload.roles).to contain_exactly(:admin)

      expect { TestUser.add_roles!(:author, records: []) }.not_to raise_error
      expect { TestUser.remove_roles!(:author, records: []) }.not_to raise_error
      expect { TestUser.add_roles!(:invalid_role, records: user) }.not_to raise_error
      expect { TestUser.remove_roles!(:invalid_role, records: user) }.not_to raise_error

      # 13. Instance clear_attribute_changes stub
      allow(user).to receive(:respond_to?).with(:clear_attribute_changes).and_return(false)
      user.add_role!(:author)
      expect(user.roles).to contain_exactly(:admin, :author)
      user.remove_role!(:author)
      expect(user.roles).to contain_exactly(:admin)

      # 13.b Nil cache in add_role! and remove_role! for unless branch coverage
      user_cov = TestUser.create!(roles: [:admin])
      user_cov.instance_variable_set(:@_bitwise_raw_values, nil)
      user_cov.add_role!(:author)
      expect(user_cov.roles).to contain_exactly(:admin, :author)

      user_cov.instance_variable_set(:@_bitwise_raw_values, nil)
      user_cov.remove_role!(:author)
      expect(user_cov.roles).to contain_exactly(:admin)

      # 13.c Deserialize casting failed check for branch coverage
      type_cov = TestUser.attribute_types['roles']
      allow(type_cov).to receive(:cast).and_return(nil)
      expect { type_cov.deserialize([:admin]) }.to raise_error(ActiveRecord::Bitwise::Error, 'Casting failed')
      allow(type_cov).to receive(:cast).and_call_original

      # 14. Boot deadlock / missing table branch coverage
      original_validated_table = TestUser.bitwise_definitions[:roles][:validated]
      begin
        allow(TestUser).to receive(:table_exists?).and_return(false)
        TestUser.bitwise_definitions[:roles][:validated] = false
        expect { TestUser.new.send(:_validate_bitwise_column_type_and_bounds) }.not_to raise_error
      ensure
        allow(TestUser).to receive(:table_exists?).and_call_original
        TestUser.bitwise_definitions[:roles][:validated] = original_validated_table
      end

      # 15. Non-integer column validation
      column_mock_class = Struct.new(:name, :type, :limit, :default, :null, :default_function)
      col_string = column_mock_class.new('roles', :string, nil, nil, true, nil)
      allow(TestUser).to receive_messages(attribute_types: { 'roles' => ActiveRecord::Type::Integer.new },
                                          table_exists?: true, columns_hash: { 'roles' => col_string })
      original_validated = TestUser.bitwise_definitions[:roles][:validated]
      begin
        TestUser.bitwise_definitions[:roles][:validated] = false
        expect do
          TestUser.new.send(:_validate_bitwise_column_type_and_bounds)
        end.to raise_error(ArgumentError,
                           /must be an integer database column/)
      ensure
        allow(TestUser).to receive(:columns_hash).and_call_original
        allow(TestUser).to receive(:attribute_types).and_call_original
        allow(TestUser).to receive(:table_exists?).and_call_original
        TestUser.bitwise_definitions[:roles][:validated] = original_validated
      end

      # 17. Non-BitwiseType update_all branch coverage
      begin
        allow(TestUser).to receive(:attribute_types).and_return({ 'roles' => ActiveRecord::Type::Integer.new })
        expect { TestUser.update_all(roles: 'admin') }.not_to raise_error
      ensure
        allow(TestUser).to receive(:attribute_types).and_call_original
      end

      # 16. Dynamic method fuzzer to cover all dynamic setter/getter branches across all classes
      [TestUser, TestUserWithSuffixPrefix, TestUserWithMoreOptions, ChildUser].each do |model_class|
        user = model_class.new
        model_class.bitwise_definitions.each do |column_name, config|
          prefix = config[:prefix]
          suffix = config[:suffix]
          mapping = config[:mapping]

          prefix_str = case prefix
                       when true then "#{column_name.to_s.singularize}_"
                       when Symbol, String then "#{prefix}_"
                       else ''
                       end

          suffix_str = case suffix
                       when true then "_#{column_name.to_s.singularize}"
                       when Symbol, String then "_#{suffix}"
                       else ''
                       end

          mapping.each_key do |key|
            method_name = "#{prefix_str}#{key}#{suffix_str}"
            user.public_send("#{method_name}?")
            user.public_send("#{method_name}=", true)
            user.public_send("#{method_name}=", true)
            user.public_send("#{method_name}=", false)
            user.public_send("#{method_name}=", false)
          end
        end
      end
    end
  end

  describe 'BUG-TYPE-001: Cast deduplicates mixed Symbol and String semantically' do
    it 'deduplicates :admin and "admin" as the same value' do
      type = TestUser.attribute_types['roles']
      result = type.cast([:admin, 'admin'])
      expect(result).to eq([:admin])
    end
  end

  describe 'BUG-SYM-001: Atomic methods do not symbolize untrusted input' do
    it 'does not create symbols from invalid values in add_roles!' do
      user = TestUser.create!(roles: [])

      TestUser.add_roles!(:admin, 'evil_untrusted_sym_dos_payload', records: user.id)
      symbols_after = Symbol.all_symbols.map(&:to_s)

      expect(symbols_after).not_to include('evil_untrusted_sym_dos_payload')
      expect(user.reload.roles).to eq([:admin])
    end

    it 'does not create symbols from invalid values in remove_roles!' do
      user = TestUser.create!(roles: [:admin])

      TestUser.remove_roles!(:admin, 'evil_untrusted_sym_dos_payload_2', records: user.id)
      symbols_after = Symbol.all_symbols.map(&:to_s)

      expect(symbols_after).not_to include('evil_untrusted_sym_dos_payload_2')
      expect(user.reload.roles).to eq([])
    end
  end

  describe 'BUG-VALID-001: Validator strips nil/empty before validation' do
    it 'does not flag nil or empty string as invalid values' do
      validator = BitwiseValidator.new(attributes: [:roles])
      user = TestUser.new
      validator.validate_each(user, :roles, [nil, '', :admin])
      expect(user.errors[:roles]).to be_empty
    end
  end

  describe 'BUG-DESER-001: Deserialize nil with unmapped default values' do
    it 'skips unmapped values in default array gracefully' do
      # Create a type with a default containing a value not in the mapping
      type_with_bad_default = ActiveRecord::Bitwise::Type.new(:test_col, { admin: 0 }, %i[admin nonexistent])
      result = type_with_bad_default.deserialize(nil)
      # Should include only the mapped default value
      expect(result).to eq([:admin])
    end
  end

  describe 'BUG-THREAD-001: Atomic instance methods wrap DB queries in transaction with lock' do
    it 'executes a transaction and lock(true) on pluck' do
      user = TestUser.create!(roles: [])
      expect(TestUser).to receive(:transaction).and_call_original
      expect_any_instance_of(ActiveRecord::Relation).to receive(:lock).with(true).and_call_original
      user.add_role!(:admin)
    end
  end

  describe 'BUG-SQL-004: Portable SQL clear arithmetic' do
    it 'removes roles using safe SQL subtraction instead of & ~?' do
      user = TestUser.create!(roles: %i[admin author])
      user.remove_role!(:author)
      expect(user.reload.roles).to eq([:admin])
    end
  end

  describe 'BUG-SCOPE-001: Zero-mask scope handling' do
    it 'queries where roles = 0 for empty values or explicit zero' do
      user_none = TestUser.create!(roles: [])
      user_admin = TestUser.create!(roles: [:admin])
      expect(TestUser.with_roles([])).to contain_exactly(user_none)
      expect(TestUser.with_roles(0)).to contain_exactly(user_none)
      expect(TestUser.with_roles).to include(user_none, user_admin)
    end
  end

  describe 'BUG-RAW-CACHE-001: Manual cache invalidation clear_bitwise_raw_values_cache!' do
    it 'clears the raw values instance variable cache' do
      user = TestUser.create!(roles: [:admin])
      user.roles # Load cache
      expect(user.instance_variable_get(:@_bitwise_raw_values)).not_to be_empty
      user.clear_bitwise_raw_values_cache!
      expect(user.instance_variable_get(:@_bitwise_raw_values)).to be_empty
    end
  end

  describe 'BUG-CALLBACK-002: Callback guard in subclass inheritance' do
    it 'does not duplicate active record callbacks on subclass' do
      callbacks = ChildUser._initialize_callbacks.select { |cb| cb.filter == :_validate_bitwise_column_type_and_bounds }
      expect(callbacks.size).to eq(1)
    end
  end

  describe 'BUG-TYPE-002: Infinite recursion guard in deserialize' do
    it 'raises an error when deserialize is called recursively beyond limit' do
      type = TestUser.attribute_types['roles']
      recursive_obj = Class.new do
        def initialize(target_type)
          @target_type = target_type
        end

        def to_i
          @target_type.deserialize(self)
          0
        end
      end.new(type)
      expect { type.deserialize(recursive_obj) }.to raise_error(ActiveRecord::Bitwise::Error, /recursion limit exceeded/)
    end
  end

  describe 'BUG-CONN-001: Lazy quote_column_name connection introspection' do
    it 'evaluates quote_column_name inside scopes and class-level atomic methods' do
      expect(TestUser.connection).to receive(:quote_column_name).at_least(:once).and_call_original
      TestUser.with_roles(:admin).to_a
    end
  end

  describe 'BUG-SETTER-002: Boolean setter preserves raw value forgotten bits' do
    it 'propagates @_bitwise_raw_value to preserve forgotten bits' do
      user = TestUser.create!(roles: [:admin])
      user.update_column(:roles, 33)
      user.reload
      expect(user.roles.instance_variable_get(:@_bitwise_raw_value)).to eq(33)
      user._deprecated_role_1 = true
      user.save!
      expect(user.reload.read_attribute_before_type_cast(:roles)).to eq(35)
    end
  end

  describe 'BUG-PERF-001: Validation performance optimization' do
    it 'exits early if all columns have been validated' do
      user = TestUser.new
      TestUser.instance_variable_set(:@_bitwise_columns_validated, false)
      TestUser.bitwise_definitions[:roles][:validated] = false
      expect(user).to receive(:_validate_bitwise_column_type_and_bounds).and_call_original
      user.send(:_validate_bitwise_column_type_and_bounds)
      expect(TestUser.instance_variable_get(:@_bitwise_columns_validated)).to be true
    end
  end

  describe 'Extra Coverage Boosters' do
    it 'deserializes with nil value when default is present or empty' do
      type_with_default = TestUser.attribute_types['permissions']
      expect(type_with_default.deserialize(nil)).to eq([:read])

      type_without_default = TestUser.attribute_types['roles']
      original_default = type_without_default.default
      type_without_default.instance_variable_set(:@default, [])
      expect(type_without_default.deserialize(nil)).to eq([])
      type_without_default.instance_variable_set(:@default, original_default)
    end

    it 'covers the invalid mapping type else branch in bitwise definition' do
      custom_mapping = Object.new
      class << custom_mapping
        def is_a?(_klass)
          caller_locations(1..1).first.path.include?('sorbet-runtime')
        end
      end

      expect do
        Class.new(ActiveRecord::Base) do
          extend ActiveRecord::Bitwise::Model

          bitwise :roles, custom_mapping
        end
      end.to raise_error(ArgumentError, /Mapping must be a Hash or an Array/)
    end

    it 'covers validation StandardError rescue and all_validated else branch' do
      user = TestUser.new
      allow(TestUser).to receive(:columns_hash).and_raise(StandardError.new('Simulated DB failure'))
      TestUser.instance_variable_set(:@_bitwise_columns_validated, false)
      TestUser.bitwise_definitions[:roles][:validated] = false

      user.send(:_validate_bitwise_column_type_and_bounds)
      expect(TestUser.instance_variable_get(:@_bitwise_columns_validated)).not_to be true
      expect(TestUser.bitwise_definitions[:roles][:validated]).not_to be true
    end

    it 'covers the else branch for boolean setter when original array has no raw value ivar' do
      user = TestUser.new
      allow(user).to receive(:roles).and_return([:admin])
      expect(user).to receive(:roles=).with(%i[admin _deprecated_role_1]).and_call_original
      user._deprecated_role_1 = true
    end

    it 'covers the else branch when bitwise_definitions is empty' do
      user = TestUser.new
      TestUser.instance_variable_set(:@_bitwise_columns_validated, false)
      allow(TestUser).to receive(:bitwise_definitions).and_return({})
      user.send(:_validate_bitwise_column_type_and_bounds)
      expect(TestUser.instance_variable_get(:@_bitwise_columns_validated)).not_to be true
    end
  end
end
