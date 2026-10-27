# typed: false
# frozen_string_literal: true

# The canonical model used by most examples:
#
#   roles         admin=bit 0 (1), editor=bit 1 (2), author=bit 2 (4), subscriber=bit 3 (8)
#   permissions   read=bit 0 (1), manage=bit 1 (2), new records default to [:read]
#   legacy_roles  Array mapping admin, moderator, author, subscriber with the prefix "legacy_"
#
# Bits 4 and above of +roles+ are unmapped ("ghost") bits.
RSpec.shared_context 'with a user model' do
  let(:model) do
    build_model('users', name: 'User') do
      bitwise :roles, { admin: 0, editor: 1, author: 2, subscriber: 3 }
      bitwise :permissions, { read: 0, manage: 1 }, default: [:read]
      bitwise :legacy_roles, %i[admin moderator author subscriber], prefix: :legacy
      validates :roles, bitwise: true
    end
  end
end

# Five persisted users whose +roles+ cover the interesting combinations. They are created
# in this order, so expectations list names in this order:
#
#   none (0), admin (1), author (4), both (admin + author = 5), three (admin + author + subscriber = 13)
#
# +names_in+ turns a relation into the names of the fixtures it returns.
RSpec.shared_context 'with scope fixtures' do
  include_context 'with a user model'

  let!(:fixtures) do
    { none: [], admin: [:admin], author: [:author], both: %i[admin author], three: %i[admin author subscriber] }
      .transform_values { |roles| model.create!(roles: roles) }
  end
  let(:names_in) do
    lambda do |relation|
      ids = relation.pluck(:id)
      fixtures.select { |_name, record| ids.include?(record.id) }.keys
    end
  end
end
