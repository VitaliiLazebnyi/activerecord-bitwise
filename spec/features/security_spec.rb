# typed: false
# frozen_string_literal: true

# Hostile input: flag names and bitmasks come from forms and query strings, so none of them may
# reach SQL as text, change the statement, or touch data outside the bitwise column.
RSpec.describe 'Hostile input' do
  let(:model) { build_model { bitwise :roles, { admin: 0, editor: 1 } } }
  let(:payloads) do
    ["admin'; DROP TABLE users; --", 'admin" OR "1"="1', '1 OR 1=1', "\u0000", '%', "admin\n; DELETE FROM users"]
  end

  before do
    model.create!(roles: [:admin])
    model.create!(roles: [])
  end

  it 'turns unknown flags in the scopes into harmless statements without the payload' do
    payloads.each do |payload|
      statements = [model.with_roles(payload), model.with_any_roles(payload),
                    model.without_roles(payload), model.with_exact_roles(payload)].map(&:to_sql)

      expect(statements.join).not_to include(payload)
    end
  end

  it 'matches nothing for unknown flags in with_roles, with_any_roles and with_exact_roles' do
    results = payloads.flat_map do |payload|
      [model.with_roles(payload), model.with_any_roles(payload), model.with_exact_roles(payload)].map(&:count)
    end

    expect(results.uniq).to eq([0])
  end

  it 'ignores unknown flags in without_roles instead of interpolating them' do
    expect(payloads.map { |payload| model.without_roles(payload).count }).to all(eq(2))
  end

  it 'rejects unknown flags in where with a message that quotes them safely' do
    expect { model.where(roles: ["admin'; DROP TABLE users; --"]) }
      .to raise_error(ActiveRecord::Bitwise::UnknownValueError, /\\?"admin'; DROP TABLE users; --\\?"/)
  end

  it 'stores nothing but a bitmask when a hostile String is assigned to the column' do
    record = model.create!(roles: '1; DROP TABLE users')

    expect([model.count, raw_value(record)]).to eq([3, 0])
  end

  it 'leaves the SQL of a model without bitwise columns alone' do
    expect(build_model.where(roles: 5).to_sql).to include('5')
  end

  it 'defines no flag methods on a model without bitwise columns' do
    expect(build_model.new).not_to respond_to(:add_role!)
  end

  it 'works inside a Fiber, which has its own recursion guard' do
    record = model.first
    result = Fiber.new { record.roles }.resume

    expect(result).to eq([:admin])
  end
end
