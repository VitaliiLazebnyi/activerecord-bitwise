# frozen_string_literal: true

require 'spec_helper'

# Define Real-Life Models
class SaaSUser < ActiveRecord::Base
  self.table_name = 'saas_users'

  # SaaS Roles and Feature Flags configuration
  bitwise :roles, { admin: 0, billing_manager: 1, developer: 2, auditor: 3 }
  bitwise :features, { api_access: 0, advanced_analytics: 1, custom_domain: 2 }

  # Model Validations simulating web form inputs
  validates :roles, bitwise: true
  validates :features, bitwise: true
end

class ETLRecord < ActiveRecord::Base
  self.table_name = 'etl_records'

  # Legacy & Future flags simulating schema drift in ETL migration pipelines
  bitwise :legacy_flags, { active: 0, verified: 1, premium: 3 }
end

RSpec.describe ActiveRecord::Bitwise, 'AR_BITWISE-REQ-009: Real-Life Usage Simulations' do
  before do
    SaaSUser.delete_all
    ETLRecord.delete_all
  end

  describe 'Scenario A: SaaS Multi-Tenant High-Concurrency Race Condition Defense' do
    it 'demonstrates that traditional assignment and save fails under concurrency (race conditions)' do
      user = SaaSUser.create!(name: 'Alice', roles: [])

      # Simulate traditional non-atomic reads
      user_thread_1 = SaaSUser.find(user.id)
      user_thread_2 = SaaSUser.find(user.id)

      # Thread 1 wants to add :admin
      user_thread_1.roles = user_thread_1.roles + [:admin]
      user_thread_1.save!

      # Thread 2 wants to add :billing_manager (with stale view)
      user_thread_2.roles = user_thread_2.roles + [:billing_manager]
      user_thread_2.save!

      # Overwritten! Only billing_manager exists; admin is lost
      expect(user.reload.roles).to eq([:billing_manager])
    end

    it 'proves that atomic SQL operations (add_role!/remove_role!) guarantee absolute correctness under concurrency' do
      user = SaaSUser.create!(name: 'Bob', roles: [])

      # Spin up concurrent threads to simulate API calls or background workers adding roles
      threads = []

      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user.add_role!(:admin)
        end
      end

      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user.add_role!(:billing_manager)
        end
      end

      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user.add_role!(:developer)
        end
      end

      threads.each(&:join)

      # All concurrent additions are fully merged and preserved because updates are executed as atomic SQL bitwise OR operations
      expect(user.reload.roles).to contain_exactly(:admin, :billing_manager, :developer)
    end

    it 'proves atomic removal operations work correctly alongside additions concurrently' do
      # Start with admin and auditor
      user = SaaSUser.create!(name: 'Charlie', roles: %i[admin auditor])

      threads = []

      # Concurrent thread 1: adds developer
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user.add_role!(:developer)
        end
      end

      # Concurrent thread 2: removes auditor
      threads << Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          user.remove_role!(:auditor)
        end
      end

      threads.each(&:join)

      # Should successfully have admin and developer, but auditor is removed
      expect(user.reload.roles).to contain_exactly(:admin, :developer)
    end
  end

  describe 'Scenario B: ETL & Data Analytics Pipeline Integration' do
    it 'maps database values using schema definitions programmatically for ETL mapping metadata' do
      # Inspect schema programmatically for dynamic exporter mapping
      schema = SaaSUser.bitwise_schema(:roles)
      expect(schema).to eq({ admin: 0, billing_manager: 1, developer: 2, auditor: 3 })
    end

    it 'ingests and preserves forgotten/unmapped bits during data migration and synchronization (backward compatibility)' do
      # Imagine importing raw data from an external feed containing unmapped bits
      # Legacy bits: active (bit 0 = 1), verified (bit 1 = 2), premium (bit 3 = 8)
      # An external feed writes a raw integer 27 (1 + 2 + 8 = 11, plus unmapped bits 16 [bit 4]) to simulated database row
      record = ETLRecord.create!(external_id: 'EXT-001', legacy_flags: [])
      ActiveRecord::Base.connection.execute("UPDATE etl_records SET legacy_flags = 27 WHERE id = #{record.id}")

      # Deserialize and verify mapping
      reloaded = ETLRecord.find(record.id)
      # 27 = 1 (active) + 2 (verified) + 8 (premium) + 16 (unmapped bit 4)
      # The active, verified, and premium are recognized
      expect(reloaded.legacy_flags).to contain_exactly(:active, :verified, :premium)

      # Modify and save back: add no new roles or change legacy flags
      reloaded.legacy_flags = [:active]
      reloaded.save!

      # Raw database value should retain the unmapped bit (16), plus 1 (active) = 17
      raw_val = ActiveRecord::Base.connection.select_value("SELECT legacy_flags FROM etl_records WHERE id = #{reloaded.id}").to_i
      expect(raw_val).to eq(17)
      expect(reloaded.reload.legacy_flags).to eq([:active])
    end

    it 'protects the host application against symbol table exhaustion (Symbol DoS) from untrusted external data feeds' do
      # Feed receives an array of 80 unique malicious string values that are not part of the bitwise mapping
      external_dirty_payload = Array.new(80) { |i| "malicious_untrusted_input_#{i}" }

      user = SaaSUser.new(name: 'Dave')
      user.roles = external_dirty_payload

      # The assigned array contains the original strings because they are not converted to symbols (they are not in the mapping)
      expect(user.roles.any?(Symbol)).to be false
      expect(user.roles.all?(String)).to be true

      # The validation correctly flags them
      expect(user.valid?).to be false
      expect(user.errors[:roles].first).to include('contains invalid values:')

      # The symbol table has not been polluted with any of our malicious strings
      all_symbol_strings = Symbol.all_symbols.map(&:to_s)
      external_dirty_payload.each do |malicious_str|
        expect(all_symbol_strings).not_to include(malicious_str)
      end
    end
  end

  describe 'Scenario C: Multi-Flag Web Form Controller Simulation' do
    it 'handles Rails-like controller params with empty strings and nil values gracefully (auto-sanitization)' do
      # Simulate a typical Rails multi-select check-box param payload:
      # Browser check-boxes often send an empty string at the beginning: `["", "admin", "billing_manager"]`
      # In addition, someone could submit nil or duplicates
      form_params = {
        roles: ['', 'admin', 'billing_manager', nil, 'admin'],
        features: ['', 'api_access', 'custom_domain', 'api_access']
      }

      user = SaaSUser.new(name: 'Grace')
      user.roles = form_params[:roles]
      user.features = form_params[:features]

      # Sanitized, deduplicated, and typed correctly
      expect(user.roles).to contain_exactly(:admin, :billing_manager)
      expect(user.features).to contain_exactly(:api_access, :custom_domain)

      expect(user.valid?).to be true
      user.save!

      # Assert raw database masks are correct
      expect(user.reload.roles_before_type_cast).to eq(3) # 1 (admin) + 2 (billing_manager)
      expect(user.features_before_type_cast).to eq(5) # 1 (api_access) + 4 (custom_domain)
    end

    it 'performs elegant validations and blocks persistence of invalid states' do
      user = SaaSUser.new(name: 'System', roles: [:admin, 'invalid_role'])

      expect(user.valid?).to be false
      expect(user.errors[:roles].first).to eq('contains invalid values: invalid_role')

      # Block persistence
      expect { user.save! }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'utilizes helper prefix/suffix methods for conditional checking and atomic toggling' do
      user = SaaSUser.create!(name: 'Ivan', roles: [:developer], features: [:api_access])

      # 1. Getter helpers (admin?, api_access?, etc.)
      expect(user.admin?).to be false
      expect(user.developer?).to be true

      # 2. Setter helpers
      user.admin = true
      expect(user.roles).to contain_exactly(:admin, :developer)

      user.admin = false
      expect(user.roles).to contain_exactly(:developer)

      # 3. Bang atomic helpers
      user.admin!
      expect(user.reload.roles).to contain_exactly(:admin, :developer)
    end
  end
end
