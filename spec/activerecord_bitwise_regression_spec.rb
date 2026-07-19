# frozen_string_literal: true

require 'spec_helper'

# Model with singular/uncountable column names (regression H-1)
class SingularStatusModel < ActiveRecord::Base
  self.table_name = 'singular_models'

  bitwise :status, { active: 0, archived: 1 }
  bitwise :fish, { salmon: 0, trout: 1 }, prefix: :has
end

# Plain ActiveModel object without bitwise definitions (regression M-12)
class PlainBitwiseValidatable
  include ActiveModel::Model

  attr_accessor :roles

  validates :roles, bitwise: true
end

RSpec.describe ActiveRecord::Bitwise, 'Code review regressions' do
  before do
    ActiveRecord::Base.connection.execute('DELETE FROM users')
    ActiveRecord::Base.connection.execute('DELETE FROM singular_models')
  end

  def raw_roles(record)
    ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{record.id}")&.to_i
  end

  def plant_ghost_bit(record, raw)
    ActiveRecord::Base.connection.execute("UPDATE users SET roles = #{raw} WHERE id = #{record.id}")
    record.reload
  end

  describe 'H-1: singular and uncountable column names' do
    it 'does not recurse infinitely for a singular column name' do
      record = SingularStatusModel.create!(status: [])
      record.add_status!(:active)
      expect(record.status).to eq([:active])
      expect(record.reload.status).to eq([:active])

      record.remove_status!(:active)
      expect(record.reload.status).to eq([])
    end

    it 'does not recurse infinitely for an uncountable column name' do
      record = SingularStatusModel.create!(fish: [])
      record.add_fish!(:salmon)
      expect(record.reload.fish).to eq([:salmon])
      record.remove_fish!(:salmon)
      expect(record.reload.fish).to eq([])
    end
  end

  describe 'H-2: instance atomic methods keep the raw cache as an Integer' do
    it 'preserves forgotten bits through add_role! followed by an ordinary save' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 16)

      user.add_role!(:admin)
      expect(raw_roles(user)).to eq(17)
      expect(user.instance_variable_get(:@_bitwise_raw_values)[:roles]).to eq(17)

      user.roles = [:author]
      user.save!
      expect(raw_roles(user)).to eq(20) # ghost bit 16 + author (4)
    end
  end

  describe 'H-3: write_attribute / []= preserve forgotten bits' do
    it 'preserves ghost bits when assigning via []=' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 16)

      user[:roles] = [:author]
      user.save!
      expect(raw_roles(user)).to eq(20)
    end

    it 'preserves ghost bits when assigning via write_attribute' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 17)

      user.send(:write_attribute, :roles, [:author])
      user.save!
      expect(raw_roles(user)).to eq(20) # bit 16 kept, admin dropped, author added
    end

    it 'enforces the 100-element cap at write_attribute time' do
      user = TestUser.new
      expect { user.send(:write_attribute, :roles, Array.new(101) { :admin }) }
        .to raise_error(ArgumentError, /cannot exceed 100/)
    end
  end

  describe 'H-4: update_all preserves forgotten bits and rejects unknown values' do
    it 'preserves per-row forgotten bits' do
      ghosted = TestUser.create!(roles: [:admin])
      plain = TestUser.create!(roles: [:_deprecated_role_1])
      plant_ghost_bit(ghosted, 17)

      TestUser.where(id: [ghosted.id, plain.id]).update_all(roles: [:author])
      expect(raw_roles(ghosted)).to eq(20) # ghost 16 + author 4
      expect(raw_roles(plain)).to eq(4)
    end

    it 'raises on unknown values instead of silently zeroing the column' do
      user = TestUser.create!(roles: %i[admin author])
      expect { TestUser.update_all(roles: [:administrator]) }
        .to raise_error(ActiveRecord::Bitwise::UnknownValueError, /administrator/)
      expect(raw_roles(user)).to eq(5)
    end

    it 'passes through nil and Arel literals untouched' do
      user = TestUser.create!(roles: [:admin])

      TestUser.where(id: user.id).update_all(roles: Arel.sql('3'))
      expect(raw_roles(user)).to eq(3)

      TestUser.where(id: user.id).update_all(roles: nil)
      expect(ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{user.id}")).to be_nil
      expect(user.reload.roles).to eq([])
    end
  end

  describe 'H-5: boolean flag setters use ActiveModel boolean semantics' do
    let(:user) { TestUser.new(roles: []) }

    it 'treats form-style false values as false' do
      ['0', 'false', '', 'f', 0, false, nil].each do |falsy|
        user.roles = [:admin]
        user.admin = falsy
        expect(user.admin?).to be(false), "expected admin = #{falsy.inspect} to disable the flag"
      end
    end

    it 'treats true-ish values as true' do
      [true, '1', 'true', 1].each do |truthy|
        user.roles = []
        user.admin = truthy
        expect(user.admin?).to be(true), "expected admin = #{truthy.inspect} to enable the flag"
      end
    end
  end

  describe 'H-6: method collision defenses' do
    it 'raises when two bitwise columns would generate the same accessor' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'users'
          bitwise :roles, { admin: 0 }
          bitwise :permissions, { admin: 0 }
        end
      end.to raise_error(ActiveRecord::Bitwise::ConfigurationError, /already defined by another bitwise column/)
    end

    it 'raises when a mapping key would shadow a real database column' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'singular_models'
          bitwise :status, { name: 0 }
        end
      end.to raise_error(ActiveRecord::Bitwise::ConfigurationError, /shadow the database column/)
    end

    it 'raises when a mapping key equals the column name itself' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'singular_models'
          bitwise :status, { status: 0 }
        end
      end.to raise_error(ActiveRecord::Bitwise::ConfigurationError, /shadow the database column/)
    end

    it 'still defines the column when the table cannot be inspected' do
      klass = Class.new(ActiveRecord::Base) { self.table_name = 'users' }
      allow(klass).to receive(:table_exists?).and_raise(StandardError, 'no connection')
      expect { klass.bitwise :roles, { admin: 0 } }.not_to raise_error
    end
  end

  describe 'H-7: mapping validation' do
    def define_with_mapping(mapping)
      Class.new(ActiveRecord::Base) do
        self.table_name = 'singular_models'
        bitwise :status, mapping
      end
    end

    it 'rejects negative bit positions' do
      expect { define_with_mapping({ a: -1 }) }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /invalid bit position/)
    end

    it 'rejects positions beyond 62' do
      expect { define_with_mapping({ a: 63 }) }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /invalid bit position/)
    end

    it 'rejects duplicate bit positions' do
      expect { define_with_mapping({ a: 1, b: 1 }) }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /same bit position/)
    end

    it 'rejects non-numeric values (Symbols, arbitrary strings)' do
      expect { define_with_mapping({ a: :b }) }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /invalid bit position/)
      expect { define_with_mapping({ a: 'abc' }) }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /invalid bit position/)
    end

    it 'accepts numeric string positions' do
      klass = define_with_mapping({ a: '3' })
      expect(klass.bitwise_schema(:status)).to eq({ a: 3 })
    end

    it 'rejects duplicate keys after symbolization' do
      expect { define_with_mapping({ 'a' => 0, a: 1 }) }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /duplicate keys/)
    end

    it 'rejects defaults that are not present in the mapping' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'singular_models'
          bitwise :status, { active: 0 }, default: [:bogus]
        end
      end.to raise_error(ActiveRecord::Bitwise::ConfigurationError, /default contains values not present/)
    end
  end

  describe 'M-1/M-2: integer, zero, and nil assignment' do
    it 'persists an assigned integer verbatim, including its own unmapped bits' do
      user = TestUser.create!(roles: [:admin])
      user.roles = 33 # bit 0 (admin) + unmapped bit 5
      user.save!
      expect(raw_roles(user)).to eq(33)
    end

    it 'clears ghost bits when assigning 0' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 17)

      user.roles = 0
      user.save!
      expect(raw_roles(user)).to eq(0)
    end

    it 'clears ghost bits and persists NULL when assigning nil' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 17)

      user.roles = nil
      expect(user.roles).to eq([])
      user.save!
      expect(ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{user.id}")).to be_nil
      expect(user.reload.roles).to eq([])
    end
  end

  describe 'M-3: dup does not copy ghost bits' do
    it 'drops unmapped bits even when the duplicate is saved without reassignment' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 17)
      expect(user.roles).to eq([:admin])

      copy = user.dup
      copy.save!
      expect(raw_roles(copy)).to eq(1) # admin only, ghost bit 16 dropped
    end
  end

  describe 'M-4: raw cache stays fresh after update_column' do
    it 'merges against the persisted value, not a stale cache' do
      user = TestUser.create!(roles: [:admin]) # raw 1
      user.update_column(:roles, 2)

      user.author = true
      user.save!
      expect(raw_roles(user)).to eq(6) # 2 (persisted) + 4 (author), stale 1 not resurrected
    end

    it 'preserves ghost bits when update_columns receives a flag array' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 16)

      user.update_columns(roles: [:admin])
      expect(raw_roles(user)).to eq(17)
    end

    it 'writes NULL verbatim through update_columns' do
      user = TestUser.create!(roles: [:admin])
      user.update_columns(roles: nil)
      expect(ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{user.id}")).to be_nil
    end

    it 'ignores non-bitwise keys and non-bitwise typecasters' do
      user = TestUser.create!(roles: [:admin])
      expect { user.update_columns(type: nil) }.not_to raise_error

      allow(TestUser).to receive(:attribute_types).and_return(
        TestUser.attribute_types.merge('roles' => ActiveRecord::Type::Integer.new)
      )
      expect { user.update_columns(roles: 5) }.not_to raise_error
    ensure
      allow(TestUser).to receive(:attribute_types).and_call_original
    end
  end

  describe 'M-7/M-11: NULL rows never resurrect defaults' do
    it 'keeps getters, scopes, and persistence consistent for NULL columns' do
      user = TestUser.create!(roles: [:admin])
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = NULL WHERE id = #{user.id}")
      user.reload

      expect(user.roles).to eq([])
      expect(TestUser.with_roles(:admin)).not_to include(user)
    end

    it 'still applies defaults to new records via the attribute API' do
      expect(TestUser.new.permissions).to eq([:read])
    end
  end

  describe 'M-8: scopes are table-qualified and survive joins' do
    it 'does not produce ambiguous column references in a self-join' do
      user = TestUser.create!(roles: [:admin])
      TestUser.create!(roles: [:author])

      joined = TestUser.joins('INNER JOIN users AS other_users ON other_users.id = users.id').with_roles(:admin)
      expect(joined).to contain_exactly(user)
      expect(TestUser.joins('INNER JOIN users AS other_users ON other_users.id = users.id').without_roles(:admin).count).to eq(1)
    end
  end

  describe 'M-9: atomic methods on new records' do
    it 'raises instead of silently no-oping' do
      expect { TestUser.new.add_role!(:admin) }
        .to raise_error(ActiveRecord::ActiveRecordError, /new record/)
      expect { TestUser.new.remove_role!(:admin) }
        .to raise_error(ActiveRecord::ActiveRecordError, /new record/)
    end
  end

  describe 'M-10: subclass configuration isolation' do
    it 'does not wipe inherited definitions when a subclass re-extends Model' do
      parent = Class.new(ActiveRecord::Base) do
        self.table_name = 'users'
        bitwise :roles, { admin: 0 }
      end
      child = Class.new(parent) { extend ActiveRecord::Bitwise::Model }

      expect(child.bitwise_definitions.keys).to include(:roles)
      expect(child.bitwise_definitions[:roles]).not_to equal(parent.bitwise_definitions[:roles])
    end
  end

  describe 'M-12/S-1: validator robustness' do
    it 'does not crash on plain ActiveModel objects' do
      model = PlainBitwiseValidatable.new(roles: [:anything])
      expect { model.valid? }.not_to raise_error
      expect(model).to be_valid
    end

    it 'honors the :message option' do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = 'users'

        def self.name
          'BitwiseMessageUser'
        end

        bitwise :roles, { admin: 0 }
        validates :roles, bitwise: { message: 'is not a valid role set' }
      end

      record = klass.new(roles: [:bogus])
      expect(record).not_to be_valid
      expect(record.errors[:roles]).to eq(['is not a valid role set'])
    end

    it 'truncates reflected invalid values in the default message' do
      user = TestUser.new
      user.roles = ["x#{'y' * 200}", 'bad_two', 'bad_three', 'bad_four', 'bad_five']
      expect(user).not_to be_valid

      message = user.errors[:roles].first
      expect(message).to include('…')
      expect(message).to include('(and 2 more)')
      expect(message.length).to be < 300
    end
  end

  describe 'M-13: cast input hygiene' do
    let(:type) { TestUser.attribute_types['roles'] }

    it 'raises on uncastable inputs instead of producing garbage flags' do
      expect { type.cast({ admin: 1 }) }.to raise_error(ArgumentError, /cannot cast/)
      expect { type.cast(true) }.to raise_error(ArgumentError, /cannot cast/)
      expect { type.cast(false) }.to raise_error(ArgumentError, /cannot cast/)
    end

    it 'treats a bare numeric string like the equivalent integer bitmask' do
      expect(type.cast('5')).to eq(type.cast(5))
      expect(type.cast('5')).to eq(%i[admin author])
    end
  end

  describe 'M-6: hash query serialization details' do
    it 'serializes multiple bitwise keys in one conditions hash' do
      user = TestUser.create!(roles: [:admin], permissions: [:read])
      expect(TestUser.where(roles: [:admin], permissions: [:read])).to contain_exactly(user)
    end

    it 'leaves nil conditions and non-bitwise typecasters untouched' do
      user = TestUser.create!(roles: [:admin])
      TestUser.where(id: user.id).update_all(roles: nil)
      expect(TestUser.where(roles: nil)).to contain_exactly(TestUser.find(user.id))

      allow(TestUser).to receive(:attribute_types).and_return({ 'roles' => ActiveRecord::Type::Integer.new })
      expect { TestUser.where(roles: 'garbage').to_sql }.not_to raise_error
    ensure
      allow(TestUser).to receive(:attribute_types).and_call_original
    end
  end

  describe 'miscellaneous hardening' do
    it 'bitwise_schema returns a defensive copy and nil for unknown columns' do
      schema = TestUser.bitwise_schema(:roles)
      schema[:hacked] = 99
      expect(TestUser.bitwise_schema(:roles)).not_to have_key(:hacked)
      expect(TestUser.bitwise_schema(:nonexistent)).to be_nil
    end

    it 'hydrates the raw cache to 0 for objects without to_i' do
      user = TestUser.new
      allow(user).to receive(:read_attribute_before_type_cast).with(:roles).and_return(Object.new)
      user.roles = [:admin]
      user.save!
      expect(raw_roles(user)).to eq(1)
    end

    it 'deserializes plain and raw-marked arrays' do
      type = TestUser.attribute_types['roles']

      plain = type.deserialize([:admin])
      expect(plain).to eq([:admin])
      expect(plain.instance_variable_get(:@_bitwise_raw_value)).to eq(1)

      stamped = type.cast(17)
      expect(type.deserialize(stamped)).to eq([:admin])
      expect(type.deserialize(stamped).instance_variable_get(:@_bitwise_raw_value)).to eq(17)
    end

    it 'rehydrates the raw cache from a raw-marked in-memory array' do
      user = TestUser.create!(roles: [])
      plant_ghost_bit(user, 16)

      user.roles = [:admin] # stamps ghost 16 onto the stored array
      user.clear_bitwise_raw_values_cache!
      expect(user.roles).to eq([:admin])
      user.save!
      expect(raw_roles(user)).to eq(17)
    end

    it 'passes writes through untouched for non-bitwise typecasters' do
      user = TestUser.new
      allow(TestUser).to receive(:attribute_types).and_return(
        TestUser.attribute_types.merge('roles' => ActiveRecord::Type::Integer.new)
      )
      user.send(:write_attribute, :roles, 5)
      expect(user.read_attribute_before_type_cast(:roles)).to eq(5)
    ensure
      allow(TestUser).to receive(:attribute_types).and_call_original
    end

    it 'handles several bitwise columns in a single update_columns call' do
      user = TestUser.create!(roles: [], permissions: [])
      user.update_columns(roles: [:admin], permissions: [:read])
      expect(user.reload.roles).to eq([:admin])
      expect(user.permissions).to eq([:read])
    end

    it 'dup handles non-array attribute values' do
      user = TestUser.new(roles: nil)
      copy = user.dup
      expect(copy.roles).to eq([])
    end

    it 'allows redefining an existing bitwise column' do
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = 'users'
        bitwise :roles, { admin: 0 }
        bitwise :roles, { admin: 0, author: 1 }
      end
      expect(klass.bitwise_schema(:roles)).to eq({ admin: 0, author: 1 })
    end
  end
end
