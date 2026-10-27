# ActiveRecord::Bitwise

ActiveRecord::Bitwise is a Ruby on Rails gem providing the ability to store multiple boolean or enum-like states inside a single integer database column. While a standard Rails `enum` saves a single value as an integer/string, `activerecord-bitwise` maps an array of symbolic values to individual bits of a single integer using bitmask arithmetic.

This is useful for `roles`, `permissions`, `preferences`, or `features` mappings where a record may have zero or multiple states concurrently, without requiring junction tables (`has_and_belongs_to_many`) or unstructured JSON/array column types.

It supports **Ruby 3.2+** and **ActiveRecord 7.1+** (up to, and tested against, the 8.x series).

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'activerecord-bitwise'
```

And then execute:
```bash
bundle install
```

Or install it yourself as:
```bash
gem install activerecord-bitwise
```

## Database Migration

The target column in your database must be an `integer`. We highly recommend setting a `default: 0` and `null: false` constraint on the column to avoid database null-state issues.

> **Capacity Note:** Database integers are signed, so the sign bit is never used for flags:
> * `limit: 1` (`tinyint`) stores up to **7 flags** (1 byte)
> * `limit: 2` (`smallint`) stores up to **15 flags** (2 bytes)
> * `limit: 4` (`integer`) stores up to **31 flags** (4 bytes) - *Rails default*
> * `limit: 8` (`bigint`) stores up to **63 flags** (8 bytes)
>
> The gem validates your mapping against the column's limit on first use and raises `ArgumentError` if a bit position does not fit.

To add `activerecord-bitwise` settings to a `User` model with a column named `roles`:

```bash
rails generate migration AddRolesToUsers roles:integer
```

In the generated migration file, ensure you set the default constraint:

```ruby
# (Replace [7.1] with your current Rails version)
class AddRolesToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :roles, :integer, default: 0, null: false
  end
end
```

Then run the migration:
```bash
rails db:migrate
```

## Model Configuration

In your `ActiveRecord` model, simply define your bitwise column (the gem automatically injects into `ActiveRecord::Base`).

You can declare settings using a **Hash** (recommended, resilient to reordering) or an **Array** (where the index defines the bit offset).

```ruby
class User < ApplicationRecord
  # RECOMMENDED: Explicit Hash mapping. The integer values are bit POSITIONS
  # (1 << position), NOT masks: {admin: 0} means bit 0 (value 1), {author: 2} means bit 2 (value 4).
  # Leave a placeholder (e.g. `_deprecated_role_1: 1`) to safeguard legacy database states.
  bitwise :roles, { admin: 0, _deprecated_role_1: 1, author: 2, subscriber: 3 }

  # Defaults apply to NEW records only (they are never resurrected for persisted NULL rows).
  bitwise :permissions, { read: 0, manage: 1 }, default: [:read]

  # Array mapping is supported, but never remove or re-order entries, only append to the end.
  bitwise :legacy_roles, %i[admin moderator author subscriber], prefix: :legacy
end
```

The mapping is validated at class-definition time. The following all raise
`ActiveRecord::Bitwise::ConfigurationError` instead of silently corrupting data:

* non-integer, negative, or > 62 bit positions;
* two keys mapped to the same bit position;
* duplicate keys;
* defaults that are not present in the mapping;
* generated accessor methods that would collide with another bitwise column's
  accessors or shadow a real database column (use `prefix:`/`suffix:` to disambiguate).

### Prefix and Suffix Options

Just like standard Rails enums, you can use the `prefix` and `suffix` options to avoid method name collisions if you have multiple bitwise columns using the same names.

```ruby
class User < ApplicationRecord
  bitwise :roles, { admin: 0, author: 1 }, suffix: true
  bitwise :permissions, { admin: 0, author: 1 }, prefix: :can
end

user = User.new
user.admin_role? # => uses roles column
user.can_admin?  # => uses permissions column
```

## Usage and API

ActiveRecord::Bitwise generates dynamic getter, setter, and scope helpers tailored exactly to your config definitions.

### Active Record Operations

You can set and retrieve the entire collection using an array of symbols/strings.

```ruby
user = User.new

# Set roles using an array
user.roles = %i[admin author]
user.roles # => [:admin, :author]

# Or strings (it converts under the hood)
user.roles = ['subscriber']
user.roles # => [:subscriber]

# To clear out all values
user.roles = []
```

All ordinary write paths — the generated setter, `write_attribute`,
`user[:roles] = ...`, `update_column`, and relation-level `update_all` — go
through the same serialization and all of them preserve unmapped ("forgotten")
bits. Assigning an Integer overwrites the raw bitmask verbatim, and assigning
`0` or `nil` intentionally clears unmapped bits as well.

### Form Helpers & Strong Parameters

When dealing with standard Rails form submissions (e.g. `collection_check_boxes`), Rails often submits empty strings `""` for unchecked states. `bitwise` handles and strips out `""` and `nil` values automatically, so you don't need to manually sanitize your strong parameters:

```ruby
# The empty string is automatically ignored
user.roles = ['', 'admin', 'author']
user.roles # => [:admin, :author]
```

### Dirty Tracking (`_changed?`)

Because it integrates with `ActiveModel::Dirty`, you can check for mutations on your virtual array attributes just like standard columns:

```ruby
user = User.find(1)
user.roles = [:admin]

user.roles_changed? # => true
user.roles_was      # => []
```

### Boolean Setters and Getters

Individual accessor methods are dynamically generated allowing direct querying and mutation of single attributes.

```ruby
user = User.new

# Question methods
user.admin?  # => false
user.author? # => false

# Boolean Setters
user.admin = true
user.author = true

# Bang Methods (Sets to true and instantly saves to the database)
user.admin!

user.roles # => [:admin, :author]
user.roles_before_type_cast # => 5 (1 + 4)
```

The boolean setters use ActiveModel boolean semantics: `"0"`, `"false"`, `""`,
`"off"`, `0`, `false`, and `nil` all *disable* the flag. This matches the value a
Rails checkbox submits when unchecked, so form params can be assigned directly
without accidentally enabling flags.

### High Concurrency (SQL Atomic Methods)

Loading records, modifying arrays, and saving (`#save`) is vulnerable to race conditions in high-throughput applications. To bypass Ruby's memory layer entirely, `bitwise` offers atomic raw-SQL bit manipulation methods. These execute directly against the DB layer, bypassing dirty tracking entirely:

```ruby
# Adds the admin role via:
#   UPDATE users SET roles = COALESCE(roles, 0) | 1 WHERE id = 1
User.add_roles!(:admin, records: user.id)

# Removes the author role via database-portable subtraction:
#   UPDATE users SET roles = COALESCE(roles, 0) - (COALESCE(roles, 0) & 4) WHERE id = 1
user.remove_role!(:author)
```

Instance-level atomic methods (`add_role!`, `remove_role!`) run inside a
transaction with a row lock, then refresh the in-memory attribute from the
database. Calling them on a new (unsaved) record raises
`ActiveRecord::ActiveRecordError`. For columns whose name is already singular
(e.g. `:status`), only `add_status!`/`remove_status!` are generated. Note that
if an *enclosing* transaction is rolled back after the call, the in-memory
attribute keeps the applied value (like `update_column`); call `reload` to
re-synchronize.

### Scopes (Querying the Database)

ActiveRecord::Bitwise leverages raw bitmask SQL calculations to extract data efficiently without loading objects into memory. It creates scopes to filter your records using `#with_[attribute]` and `#without_[attribute]`. Column references are table-qualified, so the scopes remain valid under joins.

```ruby
# Find all users that have the :admin role
# (they may also be authors or subscribers)
User.with_roles(:admin)

# Find all users that have BOTH :admin and :author roles
User.with_roles(:admin, :author)

# Find all users that have EITHER :admin OR :author roles
User.with_any_roles(:admin, :author)

# Find users who are ONLY admins (and nothing else)
User.with_exact_roles(:admin)

# Find all users that do NOT have the :moderator role
User.without_roles(:moderator)
```

### Hash Conditions (`where`, `find_by`)

Bitwise values inside hash conditions are transparently serialized to their
integer bitmask with **exact-match** semantics (like Rails' native `enum`):

```ruby
User.where(roles: [:admin])          # => WHERE roles = 1  (exactly admin, nothing else)
User.where.not(roles: [:admin])      # => WHERE roles != 1
User.find_by(roles: %i[admin author]) # => WHERE roles = 5
User.where(roles: 5)                  # raw integers pass through untouched
```

Use the `with_*`/`without_*` scopes when you want subset ("has this flag")
matching rather than an exact bitmask comparison. Unknown flag values in a hash
condition raise `ActiveRecord::Bitwise::UnknownValueError` so a typo cannot
silently match the wrong rows.

## Advanced Information

### Concurrency (Optimistic Locking Fallback)

If you must mutate states in Ruby memory via arrays instead of using the atomic SQL methods described above, we advise using standard [Rails Optimistic Locking](https://api.rubyonrails.org/classes/ActiveRecord/Locking/Optimistic.html) by adding an integer `lock_version` column to your tables to prevent simultaneous process overwrites.

### Database Indexing & Full Table Scans

Standard B-Tree indexes cannot index bitwise calculations like `WHERE (roles & 1) > 0`. If you expect your table to grow to millions of rows, querying scopes against bits will trigger full sequential scans, degrading DB performance. For query-heavy systems on PostgreSQL, apply a functional index onto the bitwise column expressions you query most.

### Memory Optimization

Storing an array of settings as a single DB integer keeps rows compact and uses standard SQL bitwise operators (such as `&` and `|`), which is significantly cheaper than generalized `json` or `text` based serialization.

### Graceful Validation (Safe Assignment)

Instead of raising a fatal `500 Server Error` (like standard enums) if a user submits an invalid string payload, the `bitwise` engine holds invalid assignments in memory so you can catch them using standard Rails validations. The standard `:message` option is supported, and reflected values in the default message are truncated (first 3 values, 64 characters each) to keep error output bounded.

```ruby
class User < ApplicationRecord
  bitwise :roles, { admin: 0, author: 1 }
  validates :roles, bitwise: true
end

user.roles = %i[admin hacker]
user.valid? # => false
user.errors[:roles] # => ["contains invalid values: hacker"]
```

> **The `validate: false` behavior:** If a developer invokes `user.save(validate: false)` while an invalid payload (`"hacker"`) is held, the typecaster **drops** the invalid string during database serialization and persists only the valid subset. Batch updates behave differently: `update_all` with unknown values raises `ActiveRecord::Bitwise::UnknownValueError` instead of silently zeroing the column for every matched row.

## Known Limitations & Mitigation Strategies

This architecture has inherent physical and systemic limitations. Design around the following constraints.

### 1. The 63-Bit Limit
**Problem:** A signed `bigint` column caps at 63 flags.
**Developer Mitigation:** Only use this gem for bounded logic scopes (e.g., core user permissions, strict system states), not for dynamic tags or user-generated groupings. If you project exceeding 40-50 flags, plan a migration to `JSONB` or standard junction tables.
**Gem-Level Mitigation:** Bit positions above 62 are rejected at class-definition time, and mappings are validated against the actual column limit on first use.

### 2. "Ghost Bit" Refactoring Collisions
**Problem:** The mechanism that preserves "forgotten bits" (to prevent destructive saves during rolling deploys) becomes a liability if developers re-use bit positions. If you delete `{ author: 1 }` and add `{ editor: 1 }`, all legacy authors silently gain the new `editor` status on their next save.
**Developer Mitigation:** **Never delete or re-index keys.** Treat mappings as append-only ledgers. Leave deprecated keys as placeholders: `bitwise :roles, { _deprecated_author: 1, editor: 2 }`.
**Gem-Level Mitigation:** Duplicate bit positions within one mapping are rejected at definition time, but the gem cannot distinguish an intentional key rename from a rolling-deployment delta across releases.

### 3. Array RAM Exhaustion
**Problem:** A malicious actor bypassing UI limits could submit an HTTP array containing millions of strings, spiking server RAM during enumeration.
**Developer Mitigation:** Enforce parameter length validations at the controller boundary before model assignment.
**Gem-Level Mitigation:** **Active.** Assigned arrays are capped at `100` elements (a padded buffer above the 63-flag physical maximum that tolerates empty strings, duplicates, and typo-strings destined for validation errors); larger arrays raise `ArgumentError` on assignment.

### 4. Privilege Escalation via Mass Assignment
**Problem:** Because a single `roles: []` parameter maps to multiple isolated boolean concepts, unconditionally allowing `params.permit(roles: [])` exposes the application to privilege escalation if an attacker injects `"super_admin"` into a profile update payload.
**Developer Mitigation:** Never allow mass-assignment of bitwise arrays on public endpoints without strict filtering: `params.permit(roles: permitted_role_keys)`.
**Gem-Level Mitigation:** **None.** Parameter sanitization is an `ActionController` responsibility; the model has no awareness of the HTTP context or the current user's privileges.

### 5. Background Worker Cache-Drops (Sidekiq/ActiveJob)
**Problem:** The "forgotten bits" protection relies on in-memory state. YAML/JSON background job serializers strip unpersisted instance variables, so saving a *dirty, serialized* model inside a worker can drop unmapped legacy bits.
**Developer Mitigation:** Pass primitive IDs (`user_id`) to workers and re-fetch with `User.find(user_id)` inside the worker before mutating.
**Gem-Level Mitigation:** **None.** Background serializers intentionally flatten state; the gem cannot transfer its in-memory markers across process boundaries.

### 6. MySQL / SQLite Full Table Scans
**Problem:** Bitwise scopes (e.g., `User.with_roles(:admin)`) execute binary arithmetic (`WHERE (roles & 1) > 0`) that B-Tree indexes cannot serve, so large tables trigger sequential scans.
**Developer Mitigation:** On PostgreSQL, use functional indexes on the expressions you query. On MySQL 5.7+, bind generated virtual columns (`admin_flag AS (roles & 1)`) and index those.
**Gem-Level Mitigation:** **None.** Indexing strategies are adapter-specific and must be applied via migrations.

### 7. Read-Modify-Write Race Conditions
**Problem:** If two web requests process overlapping arrays and call `#save` concurrently, the database follows "last write wins" and one request's changes are lost.
**Developer Mitigation:** Use Rails optimistic locking (`lock_version`), or prefer the gem's atomic SQL methods (`User.add_roles!`, `user.add_role!`) over in-memory array mutation.
**Gem-Level Mitigation:** **None** for plain `#save`; the atomic methods exist precisely for this case.

### 8. STI Column Sharing
**Problem:** In Single Table Inheritance, if two sibling models map different flags onto the same integer column, changing a record's `type` reinterprets its bits under the other model's mapping.
**Developer Mitigation:** Never share a bitwise column across STI models unless the mapping is identical and inherited from the common ancestor.
**Gem-Level Mitigation:** **Passive.** Each class holds its own deep copy of its configuration, so Ruby-side state can never leak between classes — but the gem cannot defend against raw column data overlap in the database.

### 9. Allocation Overhead on Bulk Reads
**Problem:** Getters return freshly allocated frozen arrays. Iterating a huge dataset (`User.all.map(&:roles)`) allocates an array (plus symbols) per record, which adds GC pressure.
**Developer Mitigation:** For very large exports, read the raw integer (`user.roles_before_type_cast`) instead of the casted array.
**Gem-Level Mitigation:** **None.** Object allocation is the cost of exposing a casted array attribute with dirty tracking.

### 10. Opaque Raw Data
**Problem:** The database column shows an integer (e.g., `13`); support staff cannot know what it means without decoding the bitmask (`8 + 4 + 1`).
**Developer Mitigation:** Document the integer mappings externally or build admin dashboards that decode values (see `.bitwise_schema`).
**Gem-Level Mitigation:** **None.** Opacity is fundamental to bitmask storage.

### 11. BI & Analytics Friction
**Problem:** External BI tools (Metabase, Tableau) cannot use simple equality queries and must write adapter-specific bitwise SQL (`WHERE (roles & 4) > 0`).
**Developer Mitigation:** Use `.bitwise_schema` to sync definitions to your data warehouse and build decoded SQL views for analytics teams.
**Gem-Level Mitigation:** **None.** The gem operates within the Ruby/ActiveRecord boundary.

### 12. Migration & Refactoring Constraints
**Problem:** Splitting or removing a role across all rows requires careful raw-SQL data migrations that are hard to reverse.
**Developer Mitigation:** Treat the mapping as append-only. Retire roles as `_deprecated_` placeholders; add new bits for split logic and handle legacy inference at the Ruby level.
**Gem-Level Mitigation:** **None.** Complex data migrations are the developer's responsibility.

### 13. Framework Lock-in
**Problem:** Services in other languages cannot read the column without re-implementing the bit decoding.
**Developer Mitigation:** Expose decoded states via your API layer, or share the `.bitwise_schema` mapping with consuming services.
**Gem-Level Mitigation:** **None.** The schema is optimized for Ruby evaluation.

### 14. The `<<` Array Push Trap
**Problem:** Getters return frozen arrays (protecting dirty tracking), so `user.roles << :admin` raises `FrozenError`.
**Developer Mitigation:** Use reassignment (`user.roles += [:admin]`), the flag setters (`user.admin = true`), or the atomic bang methods (`user.admin!`).
**Gem-Level Mitigation:** **Active.** Freezing makes the mistake fail fast instead of silently bypassing dirty tracking.

### 15. `validate: false` Drops Invalid Values
**Problem:** `user.save(validate: false)` does not persist invalid flag strings 1:1; the typecaster drops them during serialization.
**Developer Mitigation:** Run `#valid?` and handle errors explicitly when 1:1 persistence of external input matters.
**Gem-Level Mitigation:** **Passive** for instance saves (invalid strings are dropped); **active** for `update_all`, which raises `UnknownValueError` instead.

### 16. Adapter Behavior Differences
**Problem:** SQLite, PostgreSQL, and MySQL differ in raw value coercion and indexing capabilities, so local SQLite behavior does not fully mirror production PostgreSQL/MySQL at the query-planner level.
**Developer Mitigation:** Mirror your production database in CI; do not rely on SQLite testing if you deploy on PostgreSQL/MySQL.
**Gem-Level Mitigation:** **Passive.** Raw values are coerced through `#to_i` where adapters return strings, but adapter-specific indexing cannot be configured automatically.

## Development

### Bootstrapping the Project

1. Install dependencies:
   ```bash
   bundle install
   ```

### Running the Test Suite

Execute the RSpec tests:
```bash
bundle exec rspec
```

To test against a specific ActiveRecord release:
```bash
AR_VERSION="~> 7.1.0" bundle install
AR_VERSION="~> 7.1.0" bundle exec rspec
```

### Static Analysis, Type Checking and Security

The quality tooling requires Ruby 3.3 or newer. Every task fails on any violation:

```bash
bundle exec rake rubocop    # RuboCop with rubocop-rspec, -performance, -rake, -sorbet, -thread_safety, -md
bundle exec rake typecheck  # Sorbet; lib/ is `typed: strict`
bundle exec rake reek flay  # code smells and structural duplication
bundle exec rake audit      # bundler-audit
bundle exec rake mutant     # mutation testing (mutant, free for open source)
```

### Generating Documentation

Build the YARD documentation:
```bash
bundle exec yard doc
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
