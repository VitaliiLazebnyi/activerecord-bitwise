# typed: true
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

RSpec.describe(ActiveRecord::Bitwise::Model, '#bitwise') do
  # Decision table: prefix x suffix -> name of the generated predicate for the key :admin
  # on the column :roles (singular "role").
  let(:rows) do
    [
      { prefix: nil, suffix: nil, predicate: 'admin?' },
      { prefix: false, suffix: false, predicate: 'admin?' },
      { prefix: true, suffix: nil, predicate: 'role_admin?' },
      { prefix: nil, suffix: true, predicate: 'admin_role?' },
      { prefix: true, suffix: true, predicate: 'role_admin_role?' },
      { prefix: :can, suffix: nil, predicate: 'can_admin?' },
      { prefix: nil, suffix: :flag, predicate: 'admin_flag?' },
      { prefix: 'is', suffix: 'now', predicate: 'is_admin_now?' }
    ]
  end
  # Checks every row of the table: yields a new record of a model declared with the row's affixes and the
  # base name of the generated methods, inside a failure group named after the affixes.
  let(:each_row) do
    lambda do |&check|
      rows.each do |row|
        affixes = row.slice(:prefix, :suffix)
        record = build_model { bitwise(:roles, { admin: 0 }, **affixes) }
          .new
        aggregate_failures(affixes.inspect) { check.call(record, row.fetch(:predicate).delete_suffix('?')) }
      end
    end
  end

  it 'generates the predicate the affixes name', :aggregate_failures do
    each_row.call { |record, base| expect(record).to(respond_to("#{base}?")) }
  end

  it 'generates the matching setter', :aggregate_failures do
    each_row.call { |record, base| expect(record).to(respond_to("#{base}=")) }
  end

  it 'generates the matching bang method', :aggregate_failures do
    each_row.call { |record, base| expect(record).to(respond_to("#{base}!")) }
  end

  it 'reads and writes the column through the generated names', :aggregate_failures do
    each_row.call do |record, base|
      record.public_send("#{base}=", true)

      expect(record.roles).to(eq([:admin]))
    end
  end

  context 'with a prefix' do
    it 'does not define the unprefixed predicate' do
      expect(
        build_model { bitwise(:roles, { admin: 0 }, prefix: :can) }
        .new
      ).not_to(respond_to(:admin?))
    end
  end

  context 'with prefix: true on a column that is already singular' do
    it 'uses the column name unchanged' do
      model = build_model('singular_models') { bitwise(:status, { active: 0 }, prefix: true) }

      expect(model.new).to(respond_to(:status_active?))
    end
  end

  context 'with suffix: true on an uncountable column name' do
    it 'uses the column name unchanged' do
      model = build_model('singular_models') { bitwise(:fish, { salmon: 0 }, suffix: true) }

      expect(model.new).to(respond_to(:salmon_fish?))
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

      expect(record.roles).to(eq([:admin]))
    end

    it 'routes the prefixed predicate to the second column' do
      record.can_admin = true

      expect(record.permissions).to(eq([:admin]))
    end
  end
end
