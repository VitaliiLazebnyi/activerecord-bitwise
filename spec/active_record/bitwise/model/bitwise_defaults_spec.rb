# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#bitwise' do
  let(:define) { ->(default) { build_model { bitwise :roles, { admin: 0, author: 1 }, default: default } } }

  context 'with a default' do
    it 'exposes it on the attribute type' do
      expect(define.call([:admin]).attribute_types.fetch('roles').default).to eq([:admin])
    end

    it 'records it in the column definition' do
      expect(define.call([:admin]).bitwise_definitions.fetch(:roles)).to include(default: [:admin], validated: false)
    end

    it 'applies it to new records' do
      expect(define.call([:admin]).new.roles).to eq([:admin])
    end

    it 'accepts String names and symbolizes them' do
      expect(define.call(['author']).new.roles).to eq([:author])
    end

    it 'does not apply it to a persisted record loaded with another value' do
      model = define.call([:admin])
      record = model.create!(roles: [])

      expect(model.find(record.id).roles).to eq([])
    end

    it 'does not apply it when the record is built with explicit flags' do
      expect(define.call([:admin]).new(roles: [:author]).roles).to eq([:author])
    end

    it 'does not resurrect it for a NULL column' do
      model = define.call([:admin])
      record = plant_raw_value(model.create!, nil)

      expect(record.roles).to eq([])
    end

    it 'persists the default for a created record' do
      model = define.call([:admin])

      expect(raw_value(model.create!)).to eq(1)
    end
  end

  context 'without a default' do
    it 'starts new records with no flags' do
      expect(define.call(nil).new.roles).to eq([])
    end
  end

  context 'with a default that is not in the mapping' do
    it 'raises ConfigurationError listing the unknown values' do
      expect { define.call(%i[admin zzz]) }.to raise_error(
        ActiveRecord::Bitwise::ConfigurationError,
        'Bitwise column roles default contains values not present in the mapping: ["zzz"]'
      )
    end
  end
end
