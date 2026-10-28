# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::AtomicUpdate do
  let(:layout) { ActiveRecord::Bitwise::Layout.new(:roles, { admin: 0, editor: 1 }) }
  let(:record_class) { Struct.new(:id) }

  describe '.id_of' do
    it 'is the id of a record' do
      expect(described_class.id_of(record_class.new(42))).to eq(42)
    end

    it 'is the value itself for a plain id' do
      expect(described_class.id_of(7)).to eq(7)
    end

    it 'is the value itself when its id is not public' do
      hidden_class = Class.new { define_method(:id) { 1 } }
      hidden_class.__send__(:private, :id)
      hidden = hidden_class.new

      expect(described_class.id_of(hidden)).to equal(hidden)
    end

    it 'is the value itself when its id is protected' do
      guarded_class = Class.new { define_method(:id) { 1 } }
      guarded_class.__send__(:protected, :id)
      guarded = guarded_class.new

      expect(described_class.id_of(guarded)).to equal(guarded)
    end

    it 'reads ids with the record reader' do
      record = record_class.new(3)
      allow(record).to receive(:id).and_return(99)

      expect(described_class.id_of(record)).to eq(99)
    end
  end

  describe '#plan' do
    subject(:updater) { described_class.new(:add, layout) }

    it 'maps records to their ids' do
      expect(updater.plan([:admin], [record_class.new(1), 2, record_class.new(3)]).ids).to eq([1, 2, 3])
    end

    it 'accepts a single record' do
      expect(updater.plan([:admin], record_class.new(5)).ids).to eq([5])
    end

    it 'flattens nested values into the mask' do
      plan = updater.plan([[:admin], [:editor]], [1])

      expect(plan.assignment(ActiveRecord::Base.connection).last).to eq(3)
    end

    it 'is nil without records' do
      expect(updater.plan([:admin], [])).to be_nil
    end

    it 'is nil when no value maps to a bit' do
      expect(updater.plan([:ghost], [1])).to be_nil
    end
  end
end
