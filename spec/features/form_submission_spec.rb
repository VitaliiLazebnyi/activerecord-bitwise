# typed: false
# frozen_string_literal: true

# A SaaS user model fed by multi-select / checkbox form params and by external data feeds.
RSpec.describe 'Form submissions and external data' do
  let(:saas_user) do
    build_model('saas_users', name: 'SaaSUser') do
      bitwise :roles, { admin: 0, billing_manager: 1, developer: 2, auditor: 3 }
      bitwise :features, { api_access: 0, advanced_analytics: 1, custom_domain: 2 }
      validates :roles, bitwise: true
      validates :features, bitwise: true
    end
  end
  let(:form_params) do
    {
      roles: ['', 'admin', 'billing_manager', nil, 'admin'],
      features: ['', 'api_access', 'custom_domain', 'api_access']
    }
  end

  describe 'checkbox params with blanks and duplicates' do
    it 'cleans up the roles' do
      expect(saas_user.new(form_params).roles).to eq(%i[admin billing_manager])
    end

    it 'cleans up the features' do
      expect(saas_user.new(form_params).features).to eq(%i[api_access custom_domain])
    end

    it 'is valid' do
      expect(saas_user.new(form_params.merge(name: 'Grace'))).to be_valid
    end

    it 'stores the roles bitmask' do
      saved = saas_user.create!(form_params.merge(name: 'Grace'))

      expect(raw_value(saved, :roles)).to eq(0b11)
    end

    it 'stores the features bitmask' do
      saved = saas_user.create!(form_params.merge(name: 'Grace'))

      expect(raw_value(saved, :features)).to eq(0b101)
    end
  end

  describe 'invalid params' do
    let(:invalid) { saas_user.new(name: 'System', roles: [:admin, 'invalid_role']) }

    it 'are reported by validation' do
      invalid.valid?

      expect(invalid.errors[:roles]).to eq(['contains invalid values: invalid_role'])
    end

    it 'block persistence' do
      expect { invalid.save! }
        .to raise_error(ActiveRecord::RecordInvalid, /Roles contains invalid values: invalid_role/)
    end

    it 'leave the table empty' do
      capture_error { invalid.save! }

      expect(saas_user.count).to eq(0)
    end
  end

  describe 'a feed of many untrusted values' do
    let(:payload) { Array.new(80) { unique_unmapped_name } }
    let(:record) { saas_user.new(name: 'Dave', roles: payload) }

    it 'keeps the values as Strings' do
      expect(record.roles).to all(be_a(String))
    end

    it 'flags them as invalid' do
      record.valid?

      expect(record.errors[:roles].first).to start_with('contains invalid values: ')
    end

    it 'does not grow the symbol table with them' do
      record.valid?

      expect(payload.select { |value| symbol_exists?(value) }).to eq([])
    end
  end

  describe 'rows written by an external feed' do
    let(:etl_record) do
      build_model('etl_records', name: 'EtlRecord') { bitwise :legacy_flags, { active: 0, verified: 1, premium: 3 } }
    end
    # active (1) + verified (2) + premium (8) + the unmapped bit 4 (16)
    let(:imported) { plant_raw_value(etl_record.create!(external_id: 'EXT-001'), 27, :legacy_flags) }

    it 'exposes the mapped flags' do
      expect(imported.legacy_flags).to eq(%i[active verified premium])
    end

    it 'keeps the unmapped bit when the flags are synchronized back' do
      imported.update!(legacy_flags: [:active])

      expect(raw_value(imported, :legacy_flags)).to eq(17)
    end

    it 'reads back only the mapped flags after synchronizing' do
      imported.update!(legacy_flags: [:active])

      expect(imported.reload.legacy_flags).to eq([:active])
    end
  end

  describe 'reading the mapping for an export' do
    it 'lists every role with its bit position' do
      expect(saas_user.bitwise_schema(:roles)).to eq(admin: 0, billing_manager: 1, developer: 2, auditor: 3)
    end
  end
end
