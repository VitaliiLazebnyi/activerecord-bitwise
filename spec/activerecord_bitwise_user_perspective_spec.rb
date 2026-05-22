# frozen_string_literal: true

require 'spec_helper'

# 1. Define specific transient models for user perspective testing
class UserPerspectiveUser < ActiveRecord::Base
  self.table_name = 'users'
  bitwise :roles, { admin: 0, editor: 1, viewer: 2 }
  validates :roles, bitwise: true

  # custom_limits has limit 1 (1 byte = 8 bits, signed shift 0..6)
  bitwise :custom_limits, { guest: 0, moderator: 1 }
end

class UserPerspectiveModelWithPrefixSuffix < ActiveRecord::Base
  self.table_name = 'users'
  bitwise :permissions, %i[read write], prefix: 'is', suffix: 'flag'
end

RSpec.describe ActiveRecord::Bitwise, 'User Perspective Integration Specs' do
  before do
    ActiveRecord::Base.connection.execute('DELETE FROM users')
  end

  describe 'Clean Require Safety' do
    it 'can be required in a standalone subprocess without prior loading of sorbet-runtime' do
      # Spawns a separate process to require the gem and ensure it doesn't crash on load
      success = system("bundle exec ruby -Ilib -e \"require 'activerecord-bitwise'\"")
      expect(success).to be true
    end
  end

  describe 'Section A: Attributes, Getters, Setters, and Validations' do
    it 'returns empty array by default' do
      u = UserPerspectiveUser.new
      expect(u.roles).to eq([])
    end

    it 'accepts array of symbols and serializes to integer database value' do
      u = UserPerspectiveUser.new
      u.roles = %i[admin viewer]
      u.save!

      raw_val = ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{u.id}").to_i
      expect(raw_val).to eq(5) # 1<<0 | 1<<2 = 5
    end

    it 'returns correct symbols after setting' do
      u = UserPerspectiveUser.new(roles: %i[admin editor])
      expect(u.roles).to eq(%i[admin editor])
    end

    it 'supports ActiveRecord dirty tracking on the bitwise array' do
      u = UserPerspectiveUser.create!(roles: [:viewer])
      u.roles = %i[admin viewer]
      expect(u.roles_changed?).to be true
      expect(u.roles_change).to eq([[:viewer], %i[admin viewer]])
    end

    it 'passes validations with valid symbols' do
      u = UserPerspectiveUser.new(roles: [:admin])
      expect(u.valid?).to be true
    end

    it 'fails validations with invalid/unmapped symbols' do
      u = UserPerspectiveUser.new(roles: %i[admin moderator]) # moderator not mapped in :roles
      expect(u.valid?).to be false
      expect(u.errors[:roles].first).to eq('contains invalid values: moderator')
    end

    it 'handles nil or empty values gracefully' do
      u = UserPerspectiveUser.new(roles: nil)
      expect(u.valid?).to be true
    end
  end

  describe 'Section B: Prefix and Suffix Configurations' do
    it 'generates standard dynamic helper methods' do
      u = UserPerspectiveUser.new
      u.admin = true
      expect(u.admin?).to be true
      expect(u.roles).to eq([:admin])
    end

    it 'respects prefix and suffix options' do
      p = UserPerspectiveModelWithPrefixSuffix.new
      p.is_read_flag = true
      expect(p.is_read_flag?).to be true
      expect(p.permissions).to eq([:read])
    end

    it 'performs full ActiveRecord save cycle on bang (!) methods' do
      u = UserPerspectiveUser.create!
      u.admin!
      expect(u.reload.admin?).to be true
      expect(u.roles).to eq([:admin])
    end
  end

  describe 'Section C: Method Collisions Defense' do
    it 'raises ArgumentError when a mapping key collides with ActiveRecord Base methods' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'users'
          extend ActiveRecord::Bitwise::Model

          bitwise :roles, { save: 0 }
        end
      end.to raise_error(ArgumentError, /collides with core ActiveRecord::Base/)
    end
  end

  describe 'Section D: Database Scopes' do
    let!(:u_none)   { UserPerspectiveUser.create!(roles: []) }
    let!(:u_admin)  { UserPerspectiveUser.create!(roles: [:admin]) }
    let!(:u_editor) { UserPerspectiveUser.create!(roles: [:editor]) }
    let!(:u_both)   { UserPerspectiveUser.create!(roles: %i[admin editor]) }

    it 'filters using with_roles (AND match)' do
      expect(UserPerspectiveUser.with_roles(:admin)).to contain_exactly(u_admin, u_both)
      expect(UserPerspectiveUser.with_roles(:admin, :editor)).to contain_exactly(u_both)
    end

    it 'filters with zero roles correctly' do
      expect(UserPerspectiveUser.with_roles(0)).to contain_exactly(u_none)
    end

    it 'filters using with_any_roles (OR match)' do
      expect(UserPerspectiveUser.with_any_roles(:admin, :editor)).to contain_exactly(u_admin, u_editor, u_both)
    end

    it 'filters using with_exact_roles (exact match)' do
      expect(UserPerspectiveUser.with_exact_roles(:admin, :editor)).to contain_exactly(u_both)
      expect(UserPerspectiveUser.with_exact_roles(:admin)).to contain_exactly(u_admin)
    end

    it 'filters using without_roles (NOT match)' do
      expect(UserPerspectiveUser.without_roles(:admin)).to contain_exactly(u_none, u_editor)
      expect(UserPerspectiveUser.without_roles(:admin, :editor)).to contain_exactly(u_none)
    end
  end

  describe 'Section E: Negation & Query Poisoning Defense' do
    it 'raises NotSupportedError on direct where query on bitwise attribute' do
      expect { UserPerspectiveUser.where(roles: [:admin]) }.to raise_error(ActiveRecord::Bitwise::NotSupportedError)
    end

    it 'raises NotSupportedError on direct where.not query on bitwise attribute' do
      expect { UserPerspectiveUser.where.not(roles: [:admin]) }.to raise_error(ActiveRecord::Bitwise::NotSupportedError)
    end
  end

  describe 'Section F: Atomic SQL Updates (Class and Instance levels)' do
    it 'applies instance-level add_role! and remove_role! atomically' do
      u = UserPerspectiveUser.create!(roles: [:viewer])
      u.add_role!(:editor)
      expect(u.roles).to contain_exactly(:editor, :viewer)

      u.remove_role!(:viewer)
      expect(u.roles).to eq([:editor])
    end

    it 'applies class-level add_roles! and remove_roles! atomically' do
      u1 = UserPerspectiveUser.create!(roles: [:viewer])
      u2 = UserPerspectiveUser.create!(roles: [])

      UserPerspectiveUser.add_roles!(:admin, records: [u1, u2])
      expect(u1.reload.roles).to contain_exactly(:admin, :viewer)
      expect(u2.reload.roles).to eq([:admin])

      UserPerspectiveUser.remove_roles!(:admin, records: [u1, u2])
      expect(u1.reload.roles).to eq([:viewer])
      expect(u2.reload.roles).to eq([])
    end
  end

  describe 'Section G: Safety Guarantees & Edge Cases' do
    it 'preserves unmapped bits in the database during write-backs' do
      u = UserPerspectiveUser.create!
      ActiveRecord::Base.connection.execute("UPDATE users SET roles = 16 WHERE id = #{u.id}") # set bit 4 (unmapped)

      expect(u.reload.roles).to eq([])

      u.roles = [:admin]
      u.save!

      raw_val = ActiveRecord::Base.connection.select_value("SELECT roles FROM users WHERE id = #{u.id}").to_i
      expect(raw_val).to eq(17) # bit 0 (admin) + bit 4 (unmapped)
    end

    it 'checks database column size constraints and raises ArgumentError if shift is out of bounds' do
      expect do
        Class.new(ActiveRecord::Base) do
          self.table_name = 'users'
          extend ActiveRecord::Bitwise::Model

          # custom_limits has limit 1, which allows up to 7 flags (shifts 0..6). Position 16 fails.
          bitwise :custom_limits, { super_role: 16 }
        end.new
      end.to raise_error(ArgumentError, /has limit of 1 bytes/)
    end

    it 'invalidates raw values cache upon model reload' do
      u = UserPerspectiveUser.create!(roles: [:admin])
      expect(u.roles).to eq([:admin])

      ActiveRecord::Base.connection.execute("UPDATE users SET roles = 2 WHERE id = #{u.id}") # set editor only

      u.reload
      expect(u.roles).to eq([:editor])
    end
  end
end
