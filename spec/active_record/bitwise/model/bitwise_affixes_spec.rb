# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#bitwise' do
  # Decision table: prefix x suffix -> name of the generated predicate for the key :admin
  # on the column :roles (singular "role").
  [
    { prefix: nil, suffix: nil, predicate: 'admin?' },
    { prefix: false, suffix: false, predicate: 'admin?' },
    { prefix: true, suffix: nil, predicate: 'role_admin?' },
    { prefix: nil, suffix: true, predicate: 'admin_role?' },
    { prefix: true, suffix: true, predicate: 'role_admin_role?' },
    { prefix: :can, suffix: nil, predicate: 'can_admin?' },
    { prefix: nil, suffix: :flag, predicate: 'admin_flag?' },
    { prefix: 'is', suffix: 'now', predicate: 'is_admin_now?' }
  ].each do |row|
    context "with prefix: #{row[:prefix].inspect} and suffix: #{row[:suffix].inspect}" do
      let(:record) do
        affixes = row.slice(:prefix, :suffix)
        build_model { bitwise :roles, { admin: 0 }, **affixes }.new
      end
      let(:base) { row[:predicate].delete_suffix('?') }

      it "generates #{row[:predicate]}" do
        expect(record).to respond_to(row[:predicate])
      end

      it 'generates the matching setter' do
        expect(record).to respond_to("#{base}=")
      end

      it 'generates the matching bang method' do
        expect(record).to respond_to("#{base}!")
      end

      it 'reads and writes the column through the generated names' do
        record.public_send("#{base}=", true)

        expect(record.roles).to eq([:admin])
      end
    end
  end

  context 'with a prefix' do
    it 'does not define the unprefixed predicate' do
      expect(build_model { bitwise :roles, { admin: 0 }, prefix: :can }.new).not_to respond_to(:admin?)
    end
  end

  context 'with prefix: true on a column that is already singular' do
    it 'uses the column name unchanged' do
      model = build_model('singular_models') { bitwise :status, { active: 0 }, prefix: true }

      expect(model.new).to respond_to(:status_active?)
    end
  end

  context 'with suffix: true on an uncountable column name' do
    it 'uses the column name unchanged' do
      model = build_model('singular_models') { bitwise :fish, { salmon: 0 }, suffix: true }

      expect(model.new).to respond_to(:salmon_fish?)
    end
  end

  context 'when two columns use the same keys with different affixes' do
    let(:model) do
      build_model do
        bitwise :roles, { admin: 0, author: 1 }, suffix: true
        bitwise :permissions, { admin: 0, author: 1 }, prefix: :can
      end
    end
    let(:record) { model.new }

    it 'routes the suffixed predicate to the first column' do
      record.admin_role = true

      expect(record.roles).to eq([:admin])
    end

    it 'routes the prefixed predicate to the second column' do
      record.can_admin = true

      expect(record.permissions).to eq([:admin])
    end
  end
end
