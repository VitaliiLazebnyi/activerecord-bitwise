# ActiveRecord::Bitwise

ActiveRecord::Bitwise is a Ruby on Rails gem providing the ability to store multiple boolean or enum-like states inside a single integer database column. While a standard Rails `enum` saves a single value as an integer/string, `activerecord-bitwise` maps an array of symbolic values to individual bits of a single integer utilizing bitmask arithmetic.

This is exceptionally useful for `roles`, `permissions`, `preferences`, or `features` mappings where a record may have zero or multiple states concurrently, without requiring junction tables (has_and_belongs_to_many) or unstructured JSON/array column types.

It supports **Ruby 3.2+** and **Ruby on Rails 5.0+**.

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

> **Capacity Note (Strict Sign-Bit Limits):** Standard database integers are mathematically **signed**. The gem strictly enforces this ceiling and deliberately refuses to support `unsigned` configurations, universally sacrificing exactly **one bit** of physical headroom across all column limits. Attempting to manually force the final bit throws a fatal database `Integer Out Of Range` crash. *(Why not bypass this with `unsigned`? PostgreSQL natively lacks unsigned schema integers, so forcing it breaks adapter cross-compatibility. Furthermore, allocating the outermost bit triggers "Two's Complement," converting the integer into a negative value, which violently corrupts bitwise (`&`) scope evaluation queries in dynamically-typed adapters like SQLite).*
> * `limit: 1` (`tinyint`) stores up to **7 flags** (1 byte)
> * `limit: 2` (`smallint`) stores up to **15 flags** (2 bytes)
> * `limit: 4` (`integer`) stores up to **31 flags** (4 bytes) - *Rails default*
> * `limit: 8` (`bigint`) stores up to **63 flags** (8 bytes)

To add `activerecord-bitwise` settings to a `User` model with a column named `roles`:

```bash
rails generate migration AddRolesToUsers roles:integer
```

In the generated migration file, ensure you set the default constraint:

```ruby
# (Replace [6.1] with your current Rails version)
class AddRolesToUsers < ActiveRecord::Migration[6.1]
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

You can declare settings using a **Hash** (highly recommended to prevent data corruption) or an **Array** (where index defines the bit offset).

```ruby
class User < ApplicationRecord
  # RECOMMENDED: Explicit Hash mapping. The integer values correspond to the bit shift position (e.g. 1<<0).
  # Leave a placeholder (e.g. `_deprecated_role: 1`) to safeguard legacy database states.
  bitwise :roles, { admin: 0, _deprecated_role_1: 1, author: 2, subscriber: 3 }

  # ADVANCED: Global Fallbacks (Auto-Initialization)
  # You can enforce new records to boot precisely aligned to business logic natively bypassing `#after_initialize`.
  bitwise :permissions, { read: 0, manage: 1 }, default: [:read]

  # WARNING: Array mapping is supported, but never remove or re-order logic, only append to the end.
  bitwise :legacy_roles, %i[admin moderator author subscriber]
end
```

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

### Form Helpers & Strong Parameters

When dealing with standard Rails form submissions (e.g. `collection_check_boxes`), Rails often submits empty strings `""` for unchecked states. `bitwise` gracefully handles and strips out `""` and `nil` values automatically, so you don't need to manually sanitize your strong parameters:

```ruby
# The empty string is automatically ignored
user.roles = ['', 'admin', 'author']
user.roles # => [:admin, :author]
```

### Dirty Tracking (`_changed?`)

Because it integrates seamlessly with `ActiveModel::Dirty`, you can check for mutations on your virtual array attributes just like standard columns:

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

### High Concurrency (SQL Atomic Methods)

Loading records, modifying arrays, and saving (`#save`) is vulnerable to race conditions in high-throughput applications. To bypass Ruby's memory layer entirely, `bitwise` offers atomic raw-SQL bit manipulation algorithms. These execute directly against the DB layer bypassing Dirty Trackers entirely:

```ruby
# Adds the admin role natively via: UPDATE users SET roles = roles | 1 WHERE id = 1
User.add_roles!(:admin, records: user.id)

# Removes the author role via: UPDATE users SET roles = roles & ~2 WHERE id = 1
user.remove_role!(:author)
```

### Scopes (Querying the Database)

ActiveRecord::Bitwise heavily leverages raw bitmask SQL calculations to extract data efficiently without loading objects into memory. It creates scopes to filter your records using `#with_[attribute]` and `#without_[attribute]`.

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

## Advanced Information

### Concurrency (Optimistic Locking Fallback)

If you strictly must mutate states entirely in Ruby memory via active arrays without using the native Atomic SQL methods (described above), we highly advise utilizing standard [Rails Optimistic Locking](https://api.rubyonrails.org/classes/ActiveRecord/Locking/Optimistic.html) by adding an integer `lock_version` column to your tables to organically prevent simultaneous process overwrites.

### Database Indexing & Full Table Scans

Standard B-Tree indexes cannot index bitwise hardware calculations like `WHERE (roles & 1) > 0`. If you expect your table to grow to millions of rows, querying scopes against bits will trigger full sequential scans, degrading DB performance. For query-heavy systems natively on PostgreSQL, apply a functional index or a GIN index onto the bitwise column.

### Memory Optimization

ActiveRecord::Bitwise guarantees low memory footprint. Storing an array of settings as a single DB integer prevents query inflation and utilizes standard SQL bitwise operators (such as `&` and `|`), delivering performance magnitudes faster than using generalized `json` or `text` based serialization.

### Graceful Validation (Safe Assignment)

Instead of raising a fatal `500 Server Error` (like standard enums) if a malicious user submits an invalid string payload, the `bitwise` engine holds invalid assignments in memory so you can easily catch them using standard Rails validations.

```ruby
class User < ApplicationRecord
  bitwise :roles, { admin: 0, author: 1 }
  validates :roles, bitwise: true
end

user.roles = %i[admin hacker]
user.valid? # => false
user.errors[:roles] # => ["contains invalid values: hacker"]
```

> **The `validate: false` DB Defense:** If a developer forcibly invokes `user.save(validate: false)` or a background worker invokes `.update_column` while an invalid uncoercible payload (`"hacker"`) is held, the underlying Typecaster permanently **drops** the invalid string during the database serialization phase to prevent catastrophic `ActiveRecord::SerializationFailure`. It will continuously and safely persist only the valid subsets.

## Architecture & Safety Guarantees

Building an enterprise-grade bitmask gem involves navigating several Ruby and Rails edge cases. `activerecord-bitwise` is structurally protected against the following vulnerabilities:

### 1. Non-Destructive "Forgotten Bits" Masking
In multi-node environments, destroying a legacy mapped bit from the codebase config might accidentally destroy its presence universally if a user saves a profile update. The Typecaster strictly memos the `@_bitwise_raw_value` on load. A `#save` securely overlays active code configurations over legacy configurations (`(raw_value & ~known_mask) | new_mask`) guaranteeing unknown database bit flags survive round-trips untouched.

### 2. Single Table Inheritance (STI) Isolation
STI architectures (`class Admin < User`) can silently pollute bitwise class-attributes if subclasses map identical columns differently. The load-phase strictly isolates configuration profiles using nested `class_attribute` closures ensuring STI children cannot globally mutate their parents' hardware shifts.

### 3. Fuzzer Immunization inside Scopes (HTTP 500 Defense)
Passing a malicious query like `.with_roles(params[:roles])` via automated URL fuzzing will often pass invalid payloads like `"SELECT DROP *"` into query internals. If a gem strictly validates input and raises `ArgumentError` when constructing queries, it forces the Rails controller to inherently panic causing an `HTTP 500`. ActiveRecord::Bitwise strictly drops unrecognized query keys; querying only an unrecognized key dynamically builds `where("1=0")` safely resolving to `none` over exploding natively.

### 4. Nil Database Coalescence
If deployed on legacy tables without `null: false` constraints, standard databases inject `NULL`. If `nil & 1` reaches Ruby arithmetic layers, it triggers `NoMethodError for nil:NilClass`. The initialization boot checks entirely coerce missing underlying values to `0` bridging logic faults.

### 5. Symbol Denial of Service (DoS) Prevention
It is a severe security vulnerability to execute `.to_sym` on unverified HTTP form payloads, as malicious users could exhaust server RAM by spamming randomized strings. The `ActiveRecord::Bitwise` engine enforces **Strict Stringification** internally during initialization. It never casts unverified internet payloads to symbols during assignment.

### 6. Guarding Dirty Tracking (Frozen Arrays)
Native Rails Dirty Tracking is completely blind to in-place array manipulation (e.g., `user.roles << :author`). To prevent `#save` from silently dropping these mutations, `ActiveRecord::Bitwise` explicitly returns **frozen arrays**. This completely disables `<<`, explicitly forcing you to safely reassign (`user.roles += [:author]`) to guarantee 100% Dirty Tracking reliability.

### 7. Colossal Column Type Introspection
If a developer accidentally points `bitwise :data` onto a schema column mapped to `jsonb` or `text`, Native ActiveRecord implementations dynamically crash resolving hardware Bit-Shifts. `ActiveRecord::Bitwise` hooks into Rails boots utilizing `columns_hash[attribute].type` structurally preventing assignment over structurally incompatible schema sets.

### 8. Sorbet / Static Analysis Bundling
Metaprogramming dynamically generates methods (`#admin?`, `#author=`) at runtime, which static analysis tools like **Sorbet** cannot see. Instead of merely pretending support exists, the gem physically bundles and registers a Tapioca abstraction hook `Tapioca::Dsl::Compilers::ActiveRecordBitwise` internal to its package structure. Requiring the module properly exposes all dynamic method generations directly into your Host CI environment.

### 9. The `.where` Clause Poisoning
If a developer manually queries `User.where.not(roles: [:admin])`, standard ActiveRecord casts the array to an integer (`WHERE roles != 1`). Because bitmasks represent inclusive subsets, querying standard equality mathematically breaks the entire engine (a user with roles=3 is not equal to 1, thus the user leaks through the negation). `ActiveRecord::Bitwise` defensively throws `NotSupportedError` on generic Hash queries overriding ActiveRecord entirely, forcing `.without_roles()` isolation rules.

### 10. The Boot-Deadlock Trap (`rails db:migrate` Failure)
If `ActiveRecord::Bitwise` introspects `columns_hash[attribute].type` at the class macro level (`bitwise :roles`), it will violently crash CI pipelines building empty environments because the `users` table doesn't exist yet! Introspection is lazily evaluated utilizing `Rails.application.config.after_initialize` or actively rescuing `ActiveRecord::NoDatabaseError` resolving cold-boot deployment deadlocks natively.

### 11. ActiveRecord Life-Cycle Bricking
If a developer configures `bitwise :states, { destroyed: 0, valid: 1 }`, the macro will generate `#destroyed?`, physically overwriting core `ActiveRecord::Base` instance methods locking the model entirely! The Method-Collision engine explicitly asserts against the entire `ActiveRecord::Base.instance_methods` manifest bypassing catastrophic model corruption.

### 12. Object Clone Bleeding (`#dup` Integrity)
Executing `user2 = user1.dup` cleanly shallow-copies instances. However, because `user1` holds a hidden `@_bitwise_raw_value` cache defending "Forgotten Bits" (Point 1), saving `user2` secretly copies the ghost bits of the original user! The engine safely intercepts `initialize_dup` to surgically sever cache pointers guaranteeing green-field duplications.

### 13. The Zero-State Scope Compilation Bug
Generating queries manually on unchecked form structures (e.g. `User.with_exact_roles([])`) naturally passes a `0` value. If compiled iteratively via standard maps (`WHERE (roles & 0) = 0`), this evaluates mathematically to `TRUE` universally retrieving the entire database! ActiveRecord::Bitwise rigorously bounds empty array resolutions dynamically executing strict zero-bounds `WHERE roles = 0` nullifying logic-vacuum bleeding.

### 14. Multi-Tenant ETL Schema Extrapolation
At enterprise limits, pipelines typically mirror Postgres tables into Snowflake or Redshift environments where an integer value `3` loses its semantic map. `ActiveRecord::Bitwise` introduces an external native `.bitwise_schema(:roles)` API dynamically exporting the raw structural Ruby map ensuring external downstream Python pipeline decoders stay synchronously updated exactly with the Gem's assignments.


### 15. SQLite Raw String Coercion
While Postgres deserializes table formats statically, SQLite bindings natively mutate `Integer` pulls as String outputs (`"5"`). Firing binary interactions like `"5" & 1` explicitly crashes Ruby with `NoMethodError`. Global `#to_i` wrappers aggressively override adapter bindings shielding logical mutations.

### 16. ActiveRecord `update_all` Interception
Executing `User.update_all(roles: [:admin])` normally bypasses ActiveRecord memory layer serializers, violently crashing the database by sending an Array directly into the adapter string payload. The gem natively hooks into `ActiveRecord::Relation#update_all` to dynamically execute Ruby bitmask serialization inline, allowing developers to execute batch mutations securely using Arrays natively.

### 17. "Over-Shift" Schema Disconnect Execution Halt
Because Ruby converts arbitrarily large numbers into `Bignum` instances in memory, developers might accidentally configure 35 roles against an `integer` column that physically traps at 31 bits. During the `after_initialize` hook, the gem actively queries `columns_hash[attribute]` to detect physical hardware mismatches. If the memory assignment out-scales the schema bounds, it intentionally issues a fatal `ArgumentError` preventing catastrophic data misalignments from quietly booting.

## Known Limitations & Mitigation Strategies

While highly defensive, this architecture introduces inherent physical and systemic limitations. You must design around the following constraints to prevent data corruption or catastrophic failure.

### 1. The 63-Bit Hard Wall Limiter
**Problem:** The `bigint` signed column physically caps at 63 concurrent flags. Reaching 64 flags will organically trigger database `Integer Out Of Range` crashes.
**Developer Mitigation:** Only use this gem for bounded logic scopes (e.g., core user permissions, strict system states). Do not use this for dynamic tags or user-generated groupings. Once you project exceeding 40-50 flags, immediately architect a migration to `JSONB` or standard `has_and_belongs_to_many` junction tables.
**Gem-Level Mitigation:** **None.** This is a fixed SQL standard arithmetic ceiling that Ruby logic cannot physically circumvent using native native numeric representations.

### 2. "Ghost Bit" Refactoring Collisions ("Sleeper Cell" Data Corruption)
**Problem:** The core defense mechanism that protects "Forgotten Bits" (to prevent destructive saves in multi-node environments) becomes a liability if developers re-use integers. If you delete `{ author: 1 }` and add `{ editor: 1 }`, the gem will seamlessly and silently grant all legacy authors the new `editor` status on their next save.
**Developer Mitigation:** **Never delete or re-index keys.** You must strictly treat mappings as append-only ledgers. Always leave deprecated keys as intact placeholders: `bitwise :roles, { _deprecated_author: 1, editor: 2 }`.
**Gem-Level Mitigation:** **None.** The gem intentionally honors unknown ghost bits to prevent multi-node data destruction. It has no way to logically distinguish an architectural key rename from a rolling production deployment delta.

### 3. Array RAM Exhaustion (Payload DoS Thread Lock)
**Problem:** To prevent DB bloat, the gem runs `.compact.map(&:to_sym).uniq` on assignment. If a malicious actor bypasses UI limits and submits an HTTP array containing 2,000,000 randomized strings, this array enumeration will severely spike server RAM, invoking an OOMKill that takes down the entire Ruby node.
**Developer Mitigation:** Enforce strict parameter length validations at the Controller boundary before model assignment. Do not rely exclusively on Model validations to catch excessive array lengths.
**Gem-Level Mitigation:** **Active.** The internal mapping engine imposes an instant, O(1) `.size` intercept during raw array assignments, setting a hard ceiling at `100` elements. *(Why limit to 100 instead of exactly 63? A gracefully padded buffer of ~30 spaces absorbs standard Rails empty-strings ["", "admin"], unfiltered array duplicates, and permits innocent frontend typo-strings to be securely processed and displayed by ActiveModel Error outputs, rather than punishing legitimate users with fatal HTTP 500 crashes).* If an array surpasses 100, the gem instantly raises `ArgumentError` entirely neutralizing memory inflation.

### 4. Privilege Escalation via Mass Assignment ("God Mode")
**Problem:** Because a single `roles: []` parameter maps to multiple isolated boolean concepts, unconditionally allowing `params.permit(roles: [])` exposes the application to privilege escalation if an attacker manually injects `"super_admin"` into their profile update form payload.
**Developer Mitigation:** Never allow mass-assignment of bitwise arrays on generic/public endpoints without strict filtering. Utilize dedicated endpoints for permission mutations, or strictly filter the array explicitly in the controller: `params.permit(roles: permitted_role_keys)`.
**Gem-Level Mitigation:** **None.** Parameter sanitization is inherently an `ActionController` domain boundary. The ActiveRecord model has no awareness of the HTTP context, session scope, or current user privileges to determine if a requested role assignment is authorized.

### 5. Background Worker Cache-Drops (Sidekiq/ActiveJob)
**Problem:** The "Forgotten Bits" protection heavily relies on memory instance variables (`@_bitwise_raw_value`). Relying on automated YAML/JSON background job serializers strips unpersisted instance variables across the network boundary. Saving an altered model inside a worker without this cache will permanently obliterate all unmapped legacy database bits.
**Developer Mitigation:** Never pass dirty, instantiated ActiveRecord objects into background workers. Always pass primitive IDs (`user_id`) and execute a fresh `User.find(user_id)` inside the worker execution context to safely pull the database representation into memory prior to mutation.
**Gem-Level Mitigation:** **None.** Background serializers like Sidekiq intentionally flatten state to avoid Redis buffer overflows. The gem cannot natively transfer its RAM payload across separated processes.

### 6. MySQL / SQLite Full Table Scans
**Problem:** Bitwise scopes (e.g., `User.with_roles(:admin)`) execute raw hardware binary queries (`WHERE (roles & 1) > 0`). Standard B-Tree algorithms cannot index binary math. Without specialized indexing capabilities, millions of rows will trigger massive sequential full-table scans organically degrading database query performance to zero.
**Developer Mitigation:** Only deploy on **PostgreSQL** leveraging advanced GIN/Functional bitwise indexes. If you are strictly hardware-locked into MySQL (5.7+), mathematically bind "Generated Virtual Columns" (`admin_flag AS (roles & 1)`) and attach B-Tree indexes directly to all virtual boolean columns.
**Gem-Level Mitigation:** **None.** Indexing strategies are database adapter-specific configurations and must be applied natively via active migrations.

### 7. The "Read-Modify-Write" Mutex Lock (Race Condition Data Loss)
**Problem:** If two separate web requests process overlapping arrays and call `#save` at the exact same millisecond, the database write will obey the "Last Write Wins" rule. One of the user's intended role additions will literally be overridden and destroyed by the other concurrent request without warning.
**Developer Mitigation:** You must use standard Rails Optimistic Locking by adding an integer `lock_version` column to your tables, or strictly use the gem's native atomic raw-SQL update methods (`User.add_roles!`) instead of mutating Ruby arrays natively.
**Gem-Level Mitigation:** **None.** The `#save` method belongs to ActiveRecord. The gem cannot natively enforce database row-level locking on generic `#save` calls without severely degrading application throughput.

### 8. The "STI Type Hijack" (Cross-Model Leak)
**Problem:** In Single Table Inheritance (STI), if `Admin` and `Customer` models map to the same `roles` integer column but define completely different enum options, changing a record's `type` attribute will maliciously shift its database binary map. A `Customer` opting into `wants_newsletter: 0` will suddenly evaluation as `has_super_admin: 0` if their type changes and the new model shares the bit integer.
**Developer Mitigation:** Never share the same bitwise column name across polymorphic or STI models unless the internal mapping configurations are 100% physically identical and inherited from the core abstract class.
**Gem-Level Mitigation:** **Passive.** The gem strongly isolates its class-attribute caches so models don't pollute each other in Ruby memory, but it cannot physically defend against raw DB column data overlaps.

### 9. Garbage Collection Thrashing (Memory Allocation Complexity)
**Problem:** To strictly maintain Rails' `Dirty Tracking` functionality safely, the gem generates operations functionally and returns explicitly `frozen` Arrays upon accessing virtual getters (e.g. `user.roles`). If an application iterates over an immense dataset in an API JSON-serializer loop like `User.all.map(&:roles)`, the engine constructs a brand new frozen Array populated with newly allocated Symbols *for every individual record*. For 10,000 users, it instantly generates 10,000 Arrays and hundreds of thousands of isolated Object allocations, triggering a massive $O(N \\times V)$ memory spike.
**Developer Mitigation:** Strictly avoid triggering bitwise Array abstractions inside massive `O(N)` loop enumerations. For massive API JSON payloads, leverage the underlying native hardware integer (`user.roles_before_type_cast`) instead of the virtual Ruby array to prevent your Ruby Garbage Collector (GC) from violently halting the main Puma thread to sweep objects.
**Gem-Level Mitigation:** **None.** Continuous Ruby object allocation is the unavoidable architectural tradeoff required to mimic mapped complex ActiveModel attributes safely without permanently destroying the `ActiveModel::Dirty` tracker engine instance-wide.

### 10. "Black Box" Database Debugging (Obfuscated Raw Data)
**Problem:** Looking directly at the database column shows a seemingly random integer (e.g., `13`). Database administrators and support agents cannot intuitively know what `13` means without reverse-engineering the bitwise math (`8 + 4 + 1`).
**Developer Mitigation:** Document the integer mappings externally or provide internal administrative dashboards that safely decode the values into human-readable strings.
**Gem-Level Mitigation:** **None.** This obfuscation is the fundamental nature of bitmask architectures.

### 11. Business Intelligence (BI) & Analytics Friction
**Problem:** External BI tools (Metabase, Tableau) connected to read-replicas do not understand Ruby. Data analysts cannot use simple `LIKE` or equality queries and must resort to complex, adapter-specific bitwise SQL (`WHERE (roles & 4) > 0`), creating significant friction for non-engineering teams.
**Developer Mitigation:** Use the gem's `.bitwise_schema` export feature to sync definitions to your data warehouse (e.g., Snowflake) and construct decoded SQL views or materialized derived tables for the analytics team to query against.
**Gem-Level Mitigation:** **None.** The gem operates strictly within the Ruby/ActiveRecord boundary.

### 12. Migration & Refactoring Hell (Immutable Contract)
**Problem:** Over time, business logic changes. If you must forcibly remove a role across all users or split one role into two, writing the zero-downtime raw SQL data migration is incredibly dangerous, highly prone to errors, and difficult to reverse safely.
**Developer Mitigation:** Strictly treat the mapping as an append-only ledger. If a role must be retired, leave it as a `_deprecated_` placeholder. If logic must be split, add new bits and handle the legacy inference at the Ruby method level.
**Gem-Level Mitigation:** **None.** Complex state data migrations must be handled manually by the developer.

### 13. Framework Lock-in (Portability Loss)
**Problem:** Transitioning parts of your stack away from Ruby to a Go, Node.js, or Elixir microservice means the new service cannot seamlessly read the `bitwise` column natively. You will be forced to manually port the exact bitwise integer decoding logic into the new language.
**Developer Mitigation:** Expose the decoded states exclusively via your internal JSON API / GraphQL layer rather than allowing external microservices to connect directly to the underlying SQL table.
**Gem-Level Mitigation:** **None.** The raw database schema is optimized for Ruby evaluation.

### 14. The `<<` Array Push Trap (Developer Ergonomics)
**Problem:** Because the gem returns frozen arrays to protect `ActiveModel::Dirty` tracking, developers trying to use the standard Ruby array append operator (`user.roles << :admin`) will violently crash the application in production with a `FrozenError`.
**Developer Mitigation:** Developers must retrain muscle memory to strictly use array reassignment (`user.roles += [:admin]`) or utilize the atomic bang methods (`user.admin!`).
**Gem-Level Mitigation:** **Active.** The arrays are explicitly frozen so they fail fast at runtime, preventing silent data-loss bugs that would occur if `<<` was allowed but not tracked by Rails.

### 15. The `validate: false` Data Destruction
**Problem:** Standard Rails behavior assumes `user.save(validate: false)` forcefully writes exact payload states to the database. However, this gem actively intercepts invalid uncoercible payloads during serialization and permanently silently drops them to prevent generic `SerializationFailure` crashes.
**Developer Mitigation:** Never use `validate: false` when processing external input schemas if you expect exactly 1:1 persistence. Always run `#valid?` to capture the validation errors explicitly.
**Gem-Level Mitigation:** **Passive.** The Typecaster intentionally shreds invalid strings to prioritize database boot-safety over unvalidated payload integrity.

### 16. Brittle Database Agnosticism
**Problem:** The gem severely degrades the seamless database-agnostic philosophy of Rails. SQLite strictly coerces outputs to Strings, Postgres requires functional GIN indexes, and MySQL demands Generated Virtual Columns to avoid performance death. Moving from local SQLite to production Postgres behaves radically differently at the hardware query planner level.
**Developer Mitigation:** Your CI must flawlessly mirror your production database environment natively. Do not rely on SQLite for testing if you plan to deploy on Postgres/MySQL in production.
**Gem-Level Mitigation:** **Active/Passive.** The gem provides global `#to_i` wrappers for SQLite, but cannot automatically configure adapter-specific indexing.

## Development

### Bootstrapping the Project

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```
2. Install dependencies:
   ```bash
   bundle install
   ```

### Running the Test Suite

Execute the RSpec tests:
```bash
bundle exec rspec
```

### Static Analysis and Type Checking

Run the Sorbet static type-checker:
```bash
bundle exec srb tc
```

Run RuboCop to verify style guidelines:
```bash
bundle exec rubocop
```

### Generating Documentation

Build the YARD documentation:
```bash
bundle exec yard doc
```

## License

The gem is available as open source under the terms of the [MIT License](LICENSE.txt).
