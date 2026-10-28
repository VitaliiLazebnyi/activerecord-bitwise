# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#bitwise' do
  let(:define) { ->(mapping) { build_model { bitwise :roles, mapping } } }

  context 'with a Hash mapping' do
    it 'stores the given bit positions' do
      expect(define.call({ admin: 0, author: 2 }).bitwise_schema(:roles)).to eq(admin: 0, author: 2)
    end

    it 'accepts the lowest and the highest bit position' do
      expect(define.call({ low: 0, high: 62 }).bitwise_schema(:roles)).to eq(low: 0, high: 62)
    end

    it 'accepts numeric String positions' do
      expect(define.call({ a: '3' }).bitwise_schema(:roles)).to eq(a: 3)
    end

    it 'accepts a multi-digit numeric String position' do
      expect(define.call({ a: '12' }).bitwise_schema(:roles)).to eq(a: 12)
    end

    it 'symbolizes String keys' do
      string_keyed = { a: 1 }.transform_keys(&:to_s)

      expect(define.call(string_keyed).bitwise_schema(:roles)).to eq(a: 1)
    end

    it 'accepts an empty mapping without defining any flag' do
      expect(define.call({}).bitwise_schema(:roles)).to eq({})
    end
  end

  context 'with an Array mapping whose index is the bit position' do
    it 'accepts 63 entries (positions 0..62)' do
      names = Array.new(63) { |index| :"flag_#{index}" }

      expect(define.call(names).bitwise_schema(:roles).values.last).to eq(62)
    end

    it 'rejects the 64th entry, whose position 63 is the sign bit' do
      names = Array.new(64) { |index| :"flag_#{index}" }
      message = 'Bitwise column roles mapping key flag_63 has invalid bit position 63. Positions must be ' \
                'Integers between 0 and 62; they are bit POSITIONS (1 << position), not masks.'

      expect { define.call(names) }.to raise_error(ActiveRecord::Bitwise::ConfigurationError, message)
    end
  end

  context 'with an Array mapping' do
    it 'uses the index as the bit position' do
      expect(define.call(%i[admin moderator author]).bitwise_schema(:roles)).to eq(admin: 0, moderator: 1, author: 2)
    end

    it 'accepts Strings' do
      expect(define.call(%w[a b]).bitwise_schema(:roles)).to eq(a: 0, b: 1)
    end
  end

  context 'with an invalid bit position' do
    [-1, 63, 2**64, 'abc', '63', '-1', '', 1.5, nil, :one].each do |position|
      it "rejects #{position.inspect}" do
        message = "Bitwise column roles mapping key admin has invalid bit position #{position.inspect}. " \
                  'Positions must be Integers between 0 and 62; they are bit POSITIONS (1 << position), not masks.'

        expect { define.call({ admin: position }) }
          .to raise_error(ActiveRecord::Bitwise::ConfigurationError, message)
      end
    end
  end

  context 'with a mapping that is neither Hash nor Array' do
    it 'raises Sorbet\'s TypeError naming the parameter' do
      expect { define.call('not a mapping') }
        .to raise_error(TypeError, /\AParameter 'mapping': Expected type .*, got type String/)
    end

    it 'raises for nil' do
      expect { define.call(nil) }.to raise_error(TypeError, /\AParameter 'mapping': Expected type/)
    end
  end

  context 'with a mapping that is neither Hash nor Array and Sorbet runtime checks are off' do
    around do |example|
      handler = T::Configuration.instance_variable_get(:@call_validation_error_handler)
      T::Configuration.call_validation_error_handler = ->(*) {}
      example.run
    ensure
      T::Configuration.call_validation_error_handler = handler
    end

    it 'still raises its own ArgumentError' do
      expect { define.call('not a mapping') }
        .to raise_error(ArgumentError, 'Mapping must be a Hash or an Array')
    end
  end

  context 'with two keys sharing one bit position' do
    it 'raises ConfigurationError listing the mapping' do
      expect { define.call({ a: 1, b: 1 }) }.to raise_error(
        ActiveRecord::Bitwise::ConfigurationError,
        "Bitwise column roles mapping assigns the same bit position to multiple keys: #{{ a: 1, b: 1 }.inspect}. " \
        'Values are bit POSITIONS (1 << position), not masks.'
      )
    end
  end

  context 'with keys that collide after symbolization' do
    it 'rejects a String and a Symbol spelling the same key' do
      string_and_symbol = [['a', 0], [:a, 1]].to_h

      expect { define.call(string_and_symbol) }.to raise_error(
        ActiveRecord::Bitwise::ConfigurationError,
        'Bitwise column roles mapping contains duplicate keys after symbolization'
      )
    end

    it 'rejects a repeated entry in an Array mapping' do
      expect { define.call(%i[a a]) }.to raise_error(
        ActiveRecord::Bitwise::ConfigurationError,
        'Bitwise column roles mapping contains duplicate keys after symbolization'
      )
    end
  end

  context 'when the same column is declared twice' do
    it 'keeps the later declaration' do
      model = define.call({ admin: 0 })
      # Redeclaring redefines the generated methods, which Ruby reports in verbose mode.
      without_ruby_warnings { model.bitwise :roles, { admin: 0, author: 1 } }

      expect(model.bitwise_schema(:roles)).to eq(admin: 0, author: 1)
    end
  end
end
