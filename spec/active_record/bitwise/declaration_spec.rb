# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Declaration do
  let(:layout) { ActiveRecord::Bitwise::Layout.new(:roles, { admin: 0, editor: 1 }) }
  let(:options) { ActiveRecord::Bitwise::Options.new(default: [:admin], prefix: :can, suffix: 'now') }
  let(:declaration) { described_class.new(layout, options) }

  describe '.from' do
    let(:definition) do
      { mapping: { admin: 0, editor: 1 }, default: [:editor], prefix: :can, suffix: 'now', validated: true,
        generated_methods: [] }
    end

    subject(:rebuilt) { described_class.from(:roles, definition) }

    it('rebuilds the layout') { expect(rebuilt.layout.mapping).to eq(admin: 0, editor: 1) }
    it('rebuilds the column') { expect(rebuilt.column_name).to eq(:roles) }
    it('rebuilds the defaults') { expect(rebuilt.defaults).to eq([:editor]) }
    it('rebuilds the prefix') { expect(rebuilt.method_name(:admin)).to start_with('can_') }
    it('rebuilds the suffix') { expect(rebuilt.method_name(:admin)).to end_with('_now') }
  end

  describe '#definition' do
    it 'describes the declaration for the model' do
      expect(declaration.definition(['x?'])).to eq(
        mapping: { admin: 0, editor: 1 }, default: [:admin], prefix: :can, suffix: 'now', validated: false,
        generated_methods: ['x?']
      )
    end
  end

  describe '#method_name' do
    it 'wraps the key in the prefix and suffix' do
      expect(declaration.method_name(:admin)).to eq('can_admin_now')
    end

    it 'derives the affix from the singular column name when it is true' do
      derived = described_class.new(layout, ActiveRecord::Bitwise::Options.new(default: nil, prefix: true, suffix: true))

      expect(derived.method_name(:admin)).to eq('role_admin_role')
    end

    it 'leaves the key alone without affixes' do
      bare = described_class.new(layout, ActiveRecord::Bitwise::Options.new(default: nil, prefix: nil, suffix: false))

      expect(bare.method_name(:admin)).to eq('admin')
    end
  end

  describe '#flags' do
    it 'maps each generated name to its flag' do
      expect(declaration.flags.transform_values(&:key)).to eq('can_admin_now' => :admin, 'can_editor_now' => :editor)
    end

    it 'gives every flag the column name' do
      expect(declaration.flags.values.map(&:column_name).uniq).to eq([:roles])
    end
  end

  describe '#type and #column' do
    it('is the column as a Symbol') { expect(declaration.column).to eq(:roles) }
    it('builds the attribute type') { expect(declaration.type).to be_a(ActiveRecord::Bitwise::Type) }
  end

  describe 'defaults' do
    it 'rejects a default that is not in the mapping' do
      invalid = ActiveRecord::Bitwise::Options.new(default: [:ghost], prefix: nil, suffix: nil)

      expect { described_class.new(layout, invalid) }
        .to raise_error(ActiveRecord::Bitwise::ConfigurationError, /default contains values not present.*"ghost"/)
    end
  end
end
