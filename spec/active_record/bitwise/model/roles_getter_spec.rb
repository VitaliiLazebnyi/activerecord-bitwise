# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#roles' do
  include_context 'with a user model'

  context 'with a new record' do
    it 'returns an empty array by default' do
      expect(model.new.roles).to eq([])
    end

    it 'returns the flags the record was built with' do
      expect(model.new(roles: %i[admin author]).roles).to eq(%i[admin author])
    end
  end

  context 'with a persisted record' do
    {
      0 => [],
      1 => [:admin],
      0b1010 => %i[editor subscriber],
      0b1111 => %i[admin editor author subscriber],
      0b1_0000 => [],
      0b1_0000_0101 => %i[admin author],
      nil => []
    }.each do |stored, expected_flags|
      it "decodes the stored value #{stored.inspect} into #{expected_flags.inspect}" do
        record = plant_raw_value(model.create!, stored)

        expect(record.roles).to eq(expected_flags)
      end
    end

    it 'decodes a value that the adapter returned as a String' do
      adapter_row = { id: 1, roles: '5' }.transform_keys(&:to_s)

      expect(model.instantiate(adapter_row).roles).to eq(%i[admin author])
    end
  end

  context 'with any record' do
    it 'returns a frozen array' do
      expect(model.new(roles: [:admin]).roles).to be_frozen
    end

    it 'returns a frozen array even when nothing is assigned' do
      expect(model.new.roles).to be_frozen
    end

    it 'rejects in-place mutation so that dirty tracking cannot be bypassed' do
      record = model.new(roles: [:admin])

      expect { record.roles << :author }.to raise_error(FrozenError)
    end

    it 'leaves the flags unchanged after a rejected mutation' do
      record = model.new(roles: [:admin])
      capture_error { record.roles << :author }

      expect(record.roles).to eq([:admin])
    end

    it 'supports reassignment as the mutation idiom' do
      record = model.new(roles: [:admin])
      record.roles += [:author]

      expect(record.roles).to eq(%i[admin author])
    end
  end

  context 'when a superclass already defines an unfrozen getter' do
    let(:parent) do
      build_model.tap { |klass| klass.define_method(:roles) { [:admin] } }
    end

    it 'still returns a frozen array' do
      child = build_model(parent: parent) { bitwise :roles, { admin: 0 } }

      expect(child.new.roles).to be_frozen
    end

    it 'keeps the flags the superclass returned' do
      child = build_model(parent: parent) { bitwise :roles, { admin: 0 } }

      expect(child.new.roles).to eq([:admin])
    end
  end

  context 'when read repeatedly' do
    it 'returns the same array' do
      record = model.create!(roles: [:admin])

      expect(record.roles).to equal(record.roles)
    end
  end

  context 'when it was assigned' do
    it 'returns a frozen array' do
      record = model.new
      record.roles = [:admin]

      expect(record.roles).to be_frozen
    end
  end

  context 'with the default of a new record' do
    it 'carries the raw bitmask marker' do
      expect(raw_marker_of(model.new.permissions)).to eq(0)
    end

    it 'carries the raw bitmask marker when the default was given as an Array subclass' do
      flags = Class.new(Array).new([:admin])
      custom = build_model { bitwise :roles, { admin: 0 }, default: flags }

      expect(raw_marker_of(custom.new.roles)).to eq(0)
    end
  end
end
