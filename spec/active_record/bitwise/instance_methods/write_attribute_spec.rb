# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::InstanceMethods, '#write_attribute' do
  include_context 'with a user model'

  let(:type) { model.attribute_types['roles'] }
  # admin + the unmapped bit 4 (value 16)
  let(:ghosted) { plant_raw_value(model.create!, 0b1_0001) }

  context 'when called directly' do
    it 'stores the flags' do
      record = model.new
      record.write_attribute(:roles, [:admin])

      expect(record.roles).to eq([:admin])
    end

    it 'accepts the attribute name as a String' do
      record = model.new
      record.write_attribute('roles', [:admin])

      expect(record.roles).to eq([:admin])
    end

    it 'freezes an unfrozen array' do
      record = model.new
      record.write_attribute(:roles, [:admin])

      expect(record.roles).to be_frozen
    end

    it 'keeps the unmapped bits of the stored value' do
      ghosted.write_attribute(:roles, [:author])
      ghosted.save!

      expect(raw_value(ghosted)).to eq(0b1_0100)
    end

    it 'adopts a raw bitmask marker given as a numeric String' do
      record = plant_raw_value(model.create!, 0b1)
      record.write_attribute(:roles, with_raw_marker([:admin], '17'))
      record.save!

      expect(raw_value(record)).to eq(0b1_0001)
    end

    it 'rejects more than 100 flags' do
      expect { model.new.write_attribute(:roles, Array.new(101) { :admin }) }
        .to raise_error(ArgumentError, 'Array size cannot exceed 100')
    end
  end

  context 'when called through the [] assignment' do
    it 'keeps the unmapped bits of the stored value' do
      ghosted[:roles] = [:author]
      ghosted.save!

      expect(raw_value(ghosted)).to eq(0b1_0100)
    end

    it 'accepts a String attribute name' do
      ghosted['roles'] = [:author]
      ghosted.save!

      expect(raw_value(ghosted)).to eq(0b1_0100)
    end
  end

  context 'when called through the generated setter' do
    it 'keeps the unmapped bits of the stored value' do
      ghosted.roles = [:author]
      ghosted.save!

      expect(raw_value(ghosted)).to eq(0b1_0100)
    end
  end

  context 'with a value other than flags' do
    it 'stores an Integer verbatim' do
      ghosted.write_attribute(:roles, 0b10_0010)
      ghosted.save!

      expect(raw_value(ghosted)).to eq(0b10_0010)
    end

    it 'stores nil as NULL' do
      ghosted.write_attribute(:roles, nil)
      ghosted.save!

      expect(raw_value(ghosted)).to be_nil
    end
  end

  context 'with a column that is not bitwise' do
    it 'stores the value untouched' do
      record = model.new
      record.write_attribute(:name, 'Ada')

      expect(record.name).to eq('Ada')
    end
  end

  context 'with a column whose type was replaced after declaring it bitwise' do
    it 'stores the value untouched' do
      model.attribute :roles, :integer
      record = model.new
      record.write_attribute(:roles, 5)

      expect(record.read_attribute_before_type_cast(:roles)).to eq(5)
    end
  end

  describe 'remembering the stored bitmask for the next save' do
    it 'reads unmapped bits from a value the adapter returned as a String' do
      record = model.instantiate({ id: 1, roles: '21' }.transform_keys(&:to_s))
      record.write_attribute(:roles, [:author])

      expect(type.serialize(record.roles)).to eq(0b1_0100)
    end

    it 'starts from zero when the previous value has no bitmask' do
      record = model.new
      record.write_attribute(:permissions, [:manage])

      expect(model.attribute_types['permissions'].serialize(record.permissions)).to eq(0b10)
    end

    it 'starts from zero when the previous value is NULL' do
      record = plant_raw_value(model.create!, nil)
      record.write_attribute(:roles, [:admin])

      expect(type.serialize(record.roles)).to eq(1)
    end

    it 'reads unmapped bits from a stamped array assigned earlier' do
      ghosted.roles = [:admin]
      ghosted.clear_bitwise_raw_values_cache!
      ghosted.save!

      expect(raw_value(ghosted)).to eq(0b1_0001)
    end
  end

  context 'with an Integer followed by flags' do
    it 'keeps the unmapped bits of the Integer on save' do
      record = model.create!(roles: [:admin])
      record.write_attribute(:roles, 0b1_0000_0001)
      record.write_attribute(:roles, %i[admin author])
      record.save!

      expect(raw_value(record)).to eq(0b1_0000_0101)
    end
  end

  context 'with nil followed by flags' do
    it 'drops the unmapped bits on save' do
      ghosted.write_attribute(:roles, nil)
      ghosted.write_attribute(:roles, %i[admin author])
      ghosted.save!

      expect(raw_value(ghosted)).to eq(0b101)
    end

    it 'stores NULL when saved as it is' do
      ghosted.write_attribute(:roles, nil)
      ghosted.save!

      expect(raw_value(ghosted)).to be_nil
    end
  end

  context 'with flags' do
    it 'stores a frozen array' do
      record = model.new
      record.write_attribute(:roles, [:admin])

      expect(record.read_attribute(:roles)).to be_frozen
    end
  end

  context 'when the bitwise type of the column was replaced by a subclass of it' do
    it 'still keeps the unmapped bits' do
      model.attribute :roles, Class.new(ActiveRecord::Bitwise::Type).new(:roles, model.bitwise_schema(:roles), nil)
      record = model.find(ghosted.id)
      record.update!(roles: [:editor])

      expect(raw_value(record)).to eq(0b1_0010)
    end
  end

  context 'with an attribute the model does not have' do
    it 'raises the ActiveModel error' do
      expect { model.new.write_attribute(:unknown, 1) }.to raise_error(ActiveModel::MissingAttributeError)
    end
  end

  context 'with a raw bitmask that is a Bignum' do
    let(:wide) { build_model('capacity_records') { bitwise :big, { top: 62 } } }

    it 'leaves the record clean when the same bitmask is assigned again' do
      record = wide.find(wide.create!(big: [:top]).id)
      record.big = 2**62

      expect(record.changed?).to be(false)
    end
  end
end
