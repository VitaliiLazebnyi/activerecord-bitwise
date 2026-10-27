# typed: false
# frozen_string_literal: true

# Test database schema. Column limits are chosen to exercise every capacity tier of
# the gem: 1, 2, 3 (unusual), 4 (default) and 8 bytes, plus a non-integer column.
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :users, force: true do |t|
    t.string :type
    t.string :name
    t.integer :roles, default: 0, null: true
    t.integer :permissions, default: 0, null: true
    t.integer :legacy_roles, default: 0, null: false
    t.integer :custom_limits, limit: 1, default: 0, null: false
  end

  create_table :capacity_records, force: true do |t|
    t.integer :tiny, limit: 1, default: 0, null: false
    t.integer :small, limit: 2, default: 0, null: false
    t.integer :medium, limit: 3, default: 0, null: false
    t.integer :regular, default: 0, null: false
    t.integer :big, limit: 8, default: 0, null: false
    t.string :label
  end

  create_table :saas_users, force: true do |t|
    t.string :name, null: false
    t.integer :roles, default: 0, null: false
    t.integer :features, default: 0, null: false
  end

  create_table :etl_records, force: true do |t|
    t.string :external_id, null: false
    t.integer :legacy_flags, default: 0, null: false
  end

  create_table :singular_models, force: true do |t|
    t.integer :status, default: 0, null: false
    t.integer :fish, default: 0, null: false
    t.string :name
  end
end
