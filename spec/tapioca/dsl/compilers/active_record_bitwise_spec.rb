# typed: true
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

require 'tapioca/dsl/compilers/activerecord_bitwise'

RSpec.describe(Tapioca::Dsl::Compilers::ActiveRecordBitwise) do
  # Compiles +model+ into a new recorder. The compiler is built without its constructor: Sorbet types it
  # against Tapioca's own Compiler (three arguments), while the specs run against the stand-in (one argument).
  let(:compile) do
    lambda do |model|
      recorder = RbiRecorder.new
      compiler = described_class.allocate
      compiler.instance_variable_set(:@constant, model)
      compiler.instance_variable_set(:@root, recorder)
      compiler.decorate
      recorder
    end
  end
  let(:flags) { 'T::Array[T.any(Symbol, String)]' }

  describe '.gather_constants' do
    it 'includes models that declare a bitwise column' do
      model = build_model { bitwise(:roles, { admin: 0 }) }

      expect(described_class.gather_constants).to(include(model))
    end

    it 'excludes models without bitwise columns' do
      model = build_model

      expect(described_class.gather_constants).not_to(include(model))
    end

    it 'includes subclasses that inherit bitwise columns' do
      parent = build_model { bitwise(:roles, { admin: 0 }) }
      child = build_model(parent: parent, name: 'Child')

      expect(described_class.gather_constants).to(include(child))
    end
  end

  describe '#decorate' do
    let(:model) { build_model { bitwise :roles, { admin: 0, author: 1 } } }
    let(:generated_declarations) do
      [
        ['bitwise_schema', 'T.nilable(T::Hash[Symbol, Integer])', true],
        ['roles', flags, false],
        ['roles=', flags, false],
        ['admin?', 'T::Boolean', false],
        ['admin=', 'T::Boolean', false],
        ['admin!', 'TrueClass', false],
        ['author?', 'T::Boolean', false],
        ['author=', 'T::Boolean', false],
        ['author!', 'TrueClass', false],
        ['add_role!', 'void', false],
        ['add_roles!', 'void', false],
        ['remove_role!', 'void', false],
        ['remove_roles!', 'void', false],
        ['add_roles!', 'void', true],
        ['remove_roles!', 'void', true],
        ['with_roles', 'ActiveRecord::Relation', true],
        ['with_any_roles', 'ActiveRecord::Relation', true],
        ['with_exact_roles', 'ActiveRecord::Relation', true],
        ['without_roles', 'ActiveRecord::Relation', true]
      ]
    end

    let(:affixes) do
      [
        [nil, nil, 'admin?'],
        [true, nil, 'role_admin?'],
        [nil, true, 'admin_role?'],
        [:can, nil, 'can_admin?'],
        [nil, :flag, 'admin_flag?'],
        ['is', 'now', 'is_admin_now?']
      ]
    end

    it 'declares exactly the methods the macro generates, with their return types' do
      expect(compile.call(model).triples).to(match_array(generated_declarations))
    end

    it 'declares the methods of every bitwise column' do
      two_columns = build_model { bitwise(:roles, { admin: 0 }) }
      two_columns.bitwise(:permissions, { read: 0 })

      expect(compile.call(two_columns).class_method_names).to(include('with_roles', 'with_permissions'))
    end

    it 'declares nothing for a model without bitwise columns' do
      expect(compile.call(build_model).class_method_names).to(eq(['bitwise_schema']))
    end

    # Decision table: prefix x suffix -> generated predicate names for the key :admin
    it 'declares the predicate that every combination of prefix and suffix names', :aggregate_failures do
      affixes.each do |prefix, suffix, predicate|
        affixed = build_model { bitwise(:roles, { admin: 0 }, prefix: prefix, suffix: suffix) }
        aggregate_failures(predicate) { expect(compile.call(affixed).instance_method_names).to(include(predicate)) }
      end
    end

    it 'does not declare the unprefixed predicate when a prefix is given' do
      prefixed = build_model { bitwise(:roles, { admin: 0 }, prefix: :can) }

      expect(compile.call(prefixed).instance_method_names).not_to(include('admin?'))
    end
  end

  # Tapioca is not part of the bundle the specs run in, so the compiler loads against its stand-in.
  describe 'the stand-in for the compiler base class' do
    it 'gathers nothing on its own' do
      expect(Tapioca::Dsl::Compiler.gather_constants).to(eq([]))
    end

    it 'remembers the constant it compiles, and starts without an RBI tree' do
      model = build_model
      compiler = Tapioca::Dsl::CompilerStandIn.new(model)

      expect([compiler.constant, compiler.root]).to(eq([model, nil]))
    end
  end
end
