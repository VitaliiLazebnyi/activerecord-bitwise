# typed: false
# frozen_string_literal: true

require 'tapioca/dsl/compilers/activerecord_bitwise'

RSpec.describe Tapioca::Dsl::Compilers::ActiveRecordBitwise do
  let(:recorder) { RbiRecorder.new }
  let(:compile) do
    lambda do |model|
      compiler = described_class.new(model)
      compiler.instance_variable_set(:@root, recorder)
      compiler.decorate
      recorder
    end
  end
  let(:flags) { 'T::Array[T.any(Symbol, String)]' }

  describe '.gather_constants' do
    it 'includes models that declare a bitwise column' do
      model = build_model { bitwise :roles, { admin: 0 } }

      expect(described_class.gather_constants).to include(model)
    end

    it 'excludes models without bitwise columns' do
      model = build_model

      expect(described_class.gather_constants).not_to include(model)
    end

    it 'includes subclasses that inherit bitwise columns' do
      parent = build_model { bitwise :roles, { admin: 0 } }
      child = build_model(parent: parent, name: 'Child')

      expect(described_class.gather_constants).to include(child)
    end
  end

  describe '#decorate' do
    let(:model) { build_model { bitwise :roles, { admin: 0, author: 1 } } }
    let(:generated_declarations) do
      [
        ['bitwise_schema', 'T.nilable(T::Hash[Symbol, Integer])', true],
        ['roles', flags, false], ['roles=', flags, false],
        ['admin?', 'T::Boolean', false], ['admin=', 'T::Boolean', false], ['admin!', 'TrueClass', false],
        ['author?', 'T::Boolean', false], ['author=', 'T::Boolean', false], ['author!', 'TrueClass', false],
        ['add_role!', 'void', false], ['add_roles!', 'void', false],
        ['remove_role!', 'void', false], ['remove_roles!', 'void', false],
        ['add_roles!', 'void', true], ['remove_roles!', 'void', true],
        ['with_roles', 'ActiveRecord::Relation', true], ['with_any_roles', 'ActiveRecord::Relation', true],
        ['with_exact_roles', 'ActiveRecord::Relation', true], ['without_roles', 'ActiveRecord::Relation', true]
      ]
    end

    it 'declares exactly the methods the macro generates, with their return types' do
      expect(compile.call(model).triples).to match_array(generated_declarations)
    end

    it 'declares the methods of every bitwise column' do
      two_columns = build_model do
        bitwise :roles, { admin: 0 }
        bitwise :permissions, { read: 0 }
      end

      expect(compile.call(two_columns).class_method_names).to include('with_roles', 'with_permissions')
    end

    it 'declares nothing for a model without bitwise columns' do
      expect(compile.call(build_model).class_method_names).to eq(['bitwise_schema'])
    end

    # Decision table: prefix x suffix -> generated predicate names for the key :admin
    [
      [nil, nil, 'admin?'],
      [true, nil, 'role_admin?'],
      [nil, true, 'admin_role?'],
      [:can, nil, 'can_admin?'],
      [nil, :flag, 'admin_flag?'],
      ['is', 'now', 'is_admin_now?']
    ].each do |prefix, suffix, predicate|
      it "declares #{predicate} for prefix: #{prefix.inspect} and suffix: #{suffix.inspect}" do
        affixed = build_model { bitwise :roles, { admin: 0 }, prefix: prefix, suffix: suffix }

        expect(compile.call(affixed).instance_method_names).to include(predicate)
      end
    end

    it 'does not declare the unprefixed predicate when a prefix is given' do
      prefixed = build_model { bitwise :roles, { admin: 0 }, prefix: :can }

      expect(compile.call(prefixed).instance_method_names).not_to include('admin?')
    end
  end

  # Tapioca is not part of the bundle the specs run in, so the compiler loads against its stand-in.
  describe 'the stand-in for the compiler base class' do
    it 'gathers nothing on its own' do
      expect(Tapioca::Dsl::Compiler.gather_constants).to eq([])
    end
  end
end
