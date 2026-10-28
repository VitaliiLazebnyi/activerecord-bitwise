# typed: false
# frozen_string_literal: true

RSpec.describe ActiveRecord::Bitwise::Model, '#inherited' do
  include_context 'with a user model'

  let(:child) { build_model(parent: model, name: 'Admin') }
  let(:sibling) { build_model(parent: model, name: 'Customer') }

  context 'with a subclass of a model that declares bitwise columns' do
    it 'inherits the mapping' do
      expect(child.bitwise_schema(:roles)).to eq(model.bitwise_schema(:roles))
    end

    it 'inherits the default' do
      expect(child.new.permissions).to eq([:read])
    end

    it 'holds its own copy of each definition' do
      expect(child.bitwise_definitions[:roles]).not_to equal(model.bitwise_definitions[:roles])
    end

    it 'holds its own copy of each mapping' do
      expect(child.bitwise_definitions[:roles][:mapping]).not_to equal(model.bitwise_definitions[:roles][:mapping])
    end

    it 'does not share definitions with sibling subclasses' do
      expect(child.bitwise_definitions[:roles]).not_to equal(sibling.bitwise_definitions[:roles])
    end

    it 'keeps the parent unchanged when the subclass redeclares a column' do
      child.bitwise :roles, { owner: 0 }

      expect(model.bitwise_schema(:roles)).to eq(admin: 0, editor: 1, author: 2, subscriber: 3)
    end

    it 'keeps siblings unchanged when a subclass redeclares a column' do
      child.bitwise :roles, { owner: 0 }

      expect(sibling.bitwise_schema(:roles)).to eq(admin: 0, editor: 1, author: 2, subscriber: 3)
    end

    # Redeclaring a column on the same class replaces its generated methods without Ruby's
    # "method redefined" warning.
    it 'keeps the subclass unchanged when the parent redeclares a column later', :aggregate_failures do
      child
      model.bitwise :roles, { owner: 0 }

      expect(WarningGuard.drain).to be_empty
      expect(child.bitwise_schema(:roles)).to eq(admin: 0, editor: 1, author: 2, subscriber: 3)
    end

    it 'allows the subclass to add a column of its own' do
      child.bitwise :custom_limits, { guest: 0 }

      expect(model.bitwise_definitions.keys).to eq(%i[roles permissions legacy_roles])
    end
  end

  context 'with a subclass of a model without bitwise columns' do
    it 'lets the subclass declare columns without touching the parent' do
      parent = build_model
      build_model(parent: parent) { bitwise :roles, { admin: 0 } }

      expect(parent.bitwise_definitions).to eq({})
    end
  end

  context 'when the subclass extends the Model module again' do
    it 'keeps the inherited definitions' do
      model_module = described_class
      reextended = build_model(parent: model) { extend model_module }

      expect(reextended.bitwise_definitions.keys).to eq(%i[roles permissions legacy_roles])
    end
  end

  context 'with single table inheritance' do
    before { stub_const('Admin', child) }

    it 'persists flags through the subclass' do
      expect(raw_value(child.create!(roles: [:author]))).to eq(0b100)
    end

    it 'reads flags back through the parent' do
      record = child.create!(roles: [:author])

      expect(model.find(record.id).roles).to eq([:author])
    end
  end
end
