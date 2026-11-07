# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Options do
  describe '.parse' do
    it 'reads default, prefix and suffix' do
      options = described_class.parse(default: [:admin], prefix: :can, suffix: true)

      expect([options.default, options.prefix, options.suffix]).to eq([[:admin], :can, true])
    end

    it 'leaves every option unset when none is given' do
      options = described_class.parse({})

      expect([options.default, options.prefix, options.suffix]).to eq([nil, nil, nil])
    end

    it 'rejects an unknown keyword like Ruby does' do
      expect { described_class.parse(colour: :red) }.to raise_error(ArgumentError, 'unknown keyword: :colour')
    end

    it 'names every unknown keyword' do
      expect { described_class.parse(colour: :red, size: 1) }
        .to raise_error(ArgumentError, 'unknown keywords: :colour, :size')
    end

    it 'rejects a default that is not an Array' do
      expect { described_class.parse(default: :admin) }.to raise_error(TypeError, /Parameter 'default'.*got Symbol/)
    end

    %i[prefix suffix].each do |option|
      it "rejects a #{option} that is not a name" do
        expect { described_class.parse(option => [:can]) }.to raise_error(TypeError, /Parameter '#{option}'.*got Array/)
      end

      it "accepts false as the #{option}" do
        expect(described_class.parse(option => false).public_send(option)).to be(false)
      end
    end
  end

  context 'when passed to the bitwise macro' do
    it 'rejects an unknown option' do
      expect { build_model { bitwise :roles, { admin: 0 }, colour: :red } }
        .to raise_error(ArgumentError, 'unknown keyword: :colour')
    end
  end

  describe '.affix' do
    [nil, true, false, :can, 'can'].each do |value|
      it "returns #{value.inspect} unchanged" do
        expect(described_class.affix(:prefix, value)).to eq(value)
      end
    end

    it 'returns a String as a String' do
      expect(described_class.affix(:suffix, 'can')).to be_a(String)
    end
  end
end
