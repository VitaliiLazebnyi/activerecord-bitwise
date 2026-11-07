# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#admin=' do
  include_context 'with a user model'

  let(:record) { model.new(roles: [:author]) }

  # Decision table: ActiveModel boolean semantics (the values a Rails checkbox submits).
  [false, 0, '0', 'f', 'F', 'false', 'FALSE', 'off', 'OFF', nil, ''].each do |disabling|
    it "disables the flag when assigned #{disabling.inspect}" do
      record.roles = %i[admin author]
      record.admin = disabling

      expect(record.roles).to eq([:author])
    end
  end

  [true, 1, '1', 't', 'true', 'on', 'yes', 'anything'].each do |enabling|
    it "enables the flag when assigned #{enabling.inspect}" do
      record.admin = enabling

      expect(record.roles).to eq(%i[author admin])
    end
  end

  context 'when the flag is already set' do
    it 'does not duplicate it' do
      record.roles = %i[admin author]
      record.admin = true

      expect(record.roles).to eq(%i[admin author])
    end
  end

  context 'when the flag is not set' do
    it 'leaves the other flags alone when disabling' do
      record.admin = false

      expect(record.roles).to eq([:author])
    end
  end

  context 'with unmapped bits stored in the database' do
    it 'keeps them when the flag is enabled and saved' do
      stored = plant_raw_value(model.create!, 0b1_0000_0001)
      stored.author = true
      stored.save!

      expect(raw_value(stored)).to eq(0b1_0000_0101)
    end

    it 'keeps them when the flag is disabled and saved' do
      stored = plant_raw_value(model.create!, 0b1_0000_0001)
      stored.admin = false
      stored.save!

      expect(raw_value(stored)).to eq(0b1_0000_0000)
    end
  end

  context 'when other unsaved flags were assigned' do
    it 'builds on the current in-memory flags' do
      record.roles = [:editor]
      record.admin = true

      expect(record.roles).to eq(%i[editor admin])
    end
  end

  context 'when a superclass overrides the getter with a value that is not an array' do
    it 'stores the flags built from that value' do
      parent = build_model.tap { |klass| klass.define_method(:roles) { :author } }
      child = build_model(parent: parent) { bitwise :roles, { admin: 0, author: 1 } }
      instance = child.new
      instance.admin = true

      expect(instance.read_attribute(:roles)).to eq(%i[author admin])
    end
  end

  it 'marks the column as changed' do
    record.admin = true

    expect(record.roles_changed?).to be(true)
  end
end
