# typed: false
# frozen_string_literal: true

RSpec.describe BitwiseValidator, '#validate_each' do
  let(:model) do
    build_model do
      bitwise :roles, { admin: 0, author: 1 }
      validates :roles, bitwise: true
    end
  end
  let(:errors_for) do
    lambda do |roles|
      record = model.new(roles: roles)
      record.valid?
      record.errors[:roles]
    end
  end

  context 'with only known flags' do
    [[:admin], %i[admin author], %w[admin author], [], [''], [nil, :admin], nil].each do |roles|
      it "accepts #{roles.inspect}" do
        expect(errors_for.call(roles)).to eq([])
      end
    end
  end

  context 'with unknown flags' do
    {
      one: [[:admin, 'x'], 'contains invalid values: x'],
      three: [%w[a b c], 'contains invalid values: a, b, c'],
      four: [%w[a b c d], 'contains invalid values: a, b, c (and 1 more)'],
      five: [%w[a b c d e], 'contains invalid values: a, b, c (and 2 more)']
    }.each do |label, (roles, message)|
      it "reports the message for #{label} unknown value(s)" do
        expect(errors_for.call(roles)).to eq([message])
      end
    end

    it 'reports a Symbol that is not in the mapping' do
      expect(errors_for.call([:hacker])).to eq(['contains invalid values: hacker'])
    end

    it 'reports an Integer inside an array as an unknown name' do
      expect(errors_for.call([:admin, 7])).to eq(['contains invalid values: 7'])
    end

    it 'adds exactly one error' do
      expect(errors_for.call(%w[a b c d e f]).size).to eq(1)
    end

    it 'does not report nil and blank entries' do
      expect(errors_for.call(['', nil, 'x'])).to eq(['contains invalid values: x'])
    end
  end

  context 'with a long unknown value' do
    it 'cuts a value of 65 characters to 64 plus an ellipsis' do
      value = ('a'..'z').cycle.take(65).join

      expect(errors_for.call([value])).to eq(["contains invalid values: #{value[0, 64]}…"])
    end

    it 'keeps a value of exactly 64 characters whole' do
      expect(errors_for.call(['z' * 64])).to eq(["contains invalid values: #{'z' * 64}"])
    end

    it 'keeps a short value whole' do
      expect(errors_for.call(['z' * 63])).to eq(["contains invalid values: #{'z' * 63}"])
    end
  end

  context 'with the message option' do
    let(:model) do
      build_model do
        bitwise :roles, { admin: 0 }
        validates :roles, bitwise: { message: 'is not a valid role set' }
      end
    end

    it 'uses the given message instead of the default' do
      expect(errors_for.call(['x'])).to eq(['is not a valid role set'])
    end
  end

  context 'when called directly' do
    let(:record) { model.new }

    it 'ignores a nil value' do
      described_class.new(attributes: [:roles]).validate_each(record, :roles, nil)

      expect(record.errors[:roles]).to eq([])
    end

    it 'reports a single unknown name that is not wrapped in an array' do
      described_class.new(attributes: [:roles]).validate_each(record, :roles, :hacker)

      expect(record.errors[:roles]).to eq(['contains invalid values: hacker'])
    end

    it 'ignores nil and empty-string entries that the type cast did not remove' do
      described_class.new(attributes: [:roles]).validate_each(record, :roles, [nil, '', :hacker])

      expect(record.errors[:roles]).to eq(['contains invalid values: hacker'])
    end

    it 'looks the attribute up by its Symbol name' do
      described_class.new(attributes: [:roles]).validate_each(record, 'roles', ['hacker'])

      expect(record.errors['roles']).to eq(['contains invalid values: hacker'])
    end

    it 'ignores an attribute without a bitwise definition' do
      described_class.new(attributes: [:name]).validate_each(record, :name, ['anything'])

      expect(record.errors[:name]).to eq([])
    end
  end

  context 'with a model that has no bitwise definitions at all' do
    it 'accepts any value instead of crashing' do
      plain = build_plain_validated_model.new
      plain.roles = [:anything]

      expect(plain).to be_valid
    end
  end

  describe 'limits' do
    it 'reports at most 3 values' do
      expect(described_class::MAX_REPORTED_VALUES).to eq(3)
    end

    it 'cuts values after 64 characters' do
      expect(described_class::MAX_REPORTED_LENGTH).to eq(64)
    end
  end
end
