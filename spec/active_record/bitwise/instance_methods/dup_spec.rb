# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::InstanceMethods, '#dup' do
  include_context 'with a user model'

  let(:original) { model.create!(roles: %i[admin author]) }

  context 'with a persisted record' do
    it 'returns a new record' do
      expect(original.dup).to be_new_record
    end

    it 'copies the visible flags' do
      expect(original.dup.roles).to eq(%i[admin author])
    end

    it 'saves the copied flags' do
      copy = original.dup
      copy.save!

      expect(raw_value(copy)).to eq(0b101)
    end

    it 'copies every bitwise column' do
      expect(original.dup.permissions).to eq([:read])
    end

    it 'leaves the original untouched' do
      original.dup.roles = [:editor]

      expect(original.roles).to eq(%i[admin author])
    end
  end

  context 'with unmapped bits stored in the database' do
    let(:ghosted) { plant_raw_value(original, 0b1_0000_0001) }

    it 'drops them when saved without changes' do
      copy = ghosted.dup
      copy.save!

      expect(raw_value(copy)).to eq(1)
    end

    it 'drops them when the flags are reassigned' do
      copy = ghosted.dup
      copy.roles = [:author]
      copy.save!

      expect(raw_value(copy)).to eq(0b100)
    end

    it 'keeps them on the original' do
      ghosted.dup.save!

      expect(raw_value(ghosted)).to eq(0b1_0000_0001)
    end
  end

  context 'with a NULL column' do
    it 'copies it as no flags' do
      expect(plant_raw_value(original, nil).dup.roles).to eq([])
    end
  end

  context 'with a record assigned nil' do
    it 'copies it as no flags' do
      expect(model.new(roles: nil).dup.roles).to eq([])
    end
  end

  context 'with an unsaved record' do
    it 'copies the flags' do
      expect(model.new(roles: [:editor]).dup.roles).to eq([:editor])
    end
  end
end
