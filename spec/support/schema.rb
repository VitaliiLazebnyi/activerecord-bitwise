# typed: strict
# frozen_string_literal: true

# Copyright (c) 2026 VitaliiLazebnyi

# Test database schema. Column limits are chosen to exercise every capacity tier of
# the gem: 1, 2, 3 (unusual), 4 (default) and 8 bytes, plus a non-integer column.
ActiveRecord::Migration.verbose = false

ActiveRecord::Schema.define do
  create_table :users, force: true, comment: 'The canonical bitwise model of the suite' do |t|
    t.string(:type, comment: 'Single-table inheritance')
    t.string(:name, comment: 'A plain attribute')
    t.integer(:roles, default: 0, null: true, comment: 'Bitwise: admin, editor, author, subscriber')
    t.integer(:permissions, default: 0, null: true, comment: 'Bitwise: read, manage')
    t.integer(:legacy_roles, default: 0, null: false, comment: 'Bitwise, declared with an Array mapping')
    t.integer(:custom_limits, limit: 1, default: 0, null: false, comment: 'Bitwise, one byte')
    t.index(:roles)
  end

  create_table :capacity_records, force: true, comment: 'One column per integer byte size' do |t|
    t.integer(:tiny, limit: 1, default: 0, null: false, comment: 'One byte')
    t.integer(:small, limit: 2, default: 0, null: false, comment: 'Two bytes')
    t.integer(:medium, limit: 3, default: 0, null: false, comment: 'Three bytes')
    t.integer(:regular, default: 0, null: false, comment: 'Four bytes (no limit)')
    t.integer(:big, limit: 8, default: 0, null: false, comment: 'Eight bytes')
    t.integer(:odd, limit: 5, default: 0, null: false, comment: 'Five bytes, where the database keeps it')
    t.string(:label, comment: 'A non-integer column')
  end

  create_table :saas_users, force: true, comment: 'Form submission examples' do |t|
    t.string(:name, null: false, comment: 'The user name')
    t.integer(:roles, default: 0, null: false, comment: 'Bitwise roles')
    t.integer(:features, default: 0, null: false, comment: 'Bitwise features')
  end

  create_table :etl_records, force: true, comment: 'Imported rows with legacy bitmasks' do |t|
    t.string(:external_id, null: false, comment: 'The id in the source system')
    t.integer(:legacy_flags, default: 0, null: false, comment: 'Bitwise flags written by the source system')
  end

  create_table :singular_models, force: true, comment: 'A model with a singular column name' do |t|
    t.integer(:status, default: 0, null: false, comment: 'Bitwise status')
    t.integer(:fish, default: 0, null: false, comment: 'Bitwise, a singular column name')
    t.string(:name, comment: 'A plain attribute')
  end
end
