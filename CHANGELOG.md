# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.12.0] - 2026-10-28

### Changed (breaking)

- **The minimum supported Ruby is now 3.3** (`required_ruby_version >= 3.3.0`); Ruby 3.2 is no
  longer supported or tested. ActiveRecord 7.1 to 8.x remain supported.

### Fixed

- A 3-byte integer column (MySQL `MEDIUMINT`, 23 usable signed bits) was validated as if it held
  31 flags, so a mapping with a flag at position 23..30 was accepted and could overflow when
  written. The capacity of a 3-byte column is now 23 flags.
- A bitmask outside the signed 64-bit range (for example `record.roles = 2**70`) was stored by
  SQLite as a lossy floating-point number. `Type#serialize` now raises `ActiveModel::RangeError`,
  like ActiveModel's own Integer type; `where` with such a value matches nothing.
- Array mappings did not check their bit positions: an Array of more than 63 flags was accepted
  at definition time. Positions are now validated exactly like Hash mappings (0 to 62).
- **Behavior change:** `without_<column>`, `with_exact_<column>` with no flags and `with_<column>(0)`
  ignored rows whose column is NULL, although the getter reads NULL as "no flags". They now treat NULL
  as 0 (`(col = 0 OR col IS NULL)` for the equality cases, so an index on the column stays usable;
  `COALESCE(col, 0) & mask = 0` for `without_`).
- Declaring a column again on the same class (for example after reloading a model in development)
  made Ruby print a "method redefined" warning for every generated method and scope in verbose mode
  (`ruby -w`). The earlier generated methods are now replaced without a warning.

### Added

- Mutation testing (mutant), Reek, Flay, bundler-audit, CodeQL (security-extended and
  security-and-quality), dependency review, gitleaks, OpenSSF Scorecard, actionlint and
  zizmor; all CI actions are pinned to commit SHAs with least-privilege permissions.
- A much larger, behavior-oriented spec suite (100% line and branch coverage).

### Changed

- Development dependencies upgraded to their latest releases (SimpleCov 1.x, rubocop-md 2.x, ...)
  and declared as ordinary development dependencies in the gemspec; the repository develops on
  Ruby 4.0.9 (`.ruby-version`) and CI tests Ruby 3.3, 3.4 and 4.0.
- The internal code is split into small typed classes. Two duck-typing checks are now made on the
  class instead of with `respond_to?`: an object passed to `records:` counts as a record when its
  class has a public `id` method, and the bitwise validator looks for a public class method
  `bitwise_definitions`. Only objects that answer those methods through `method_missing` (or a
  singleton method) behave differently.
- The private record helpers behind the generated methods (`_bitwise_read`,
  `_bitwise_flag_enabled?`, `_bitwise_flag_assign`, `_bitwise_flag_save`, `_bitwise_atomic_update!`)
  are now private.

## [0.11.0] - 2026-07-20

Version note: a tag typo previously published `0.10.0` to RubyGems from the
`0.1.0` tree, permanently shadowing the `0.1.x`/`0.2.x` range in the resolver.
This release therefore jumps to `0.11.0`, and the release workflow now refuses
to publish unless the tag matches `version.rb`.

### Fixed (data corruption / correctness)

- **Singular column names** (`:status`, `:fish`, ...) no longer generate a
  self-aliasing atomic method that recursed infinitely (`SystemStackError`).
- **Instance atomic methods** (`add_role!`/`remove_role!`) no longer poison the
  raw-value cache with a deserialized array, which destroyed unmapped
  ("forgotten") bits on the next save. They also now raise
  `ActiveRecord::ActiveRecordError` on new records instead of silently no-oping.
- **`write_attribute` / `record[:col] = ...`** now go through the same
  raw-bitmask stamping as the generated setter, so forgotten bits survive every
  ordinary write path.
- **`update_all`** now emits a ghost-bit-preserving SQL expression
  (`(COALESCE(col, 0) & ~known_mask) | mask`) per row, and raises
  `UnknownValueError` when given unmapped values instead of silently zeroing the
  column table-wide.
- **Boolean flag setters** use ActiveModel boolean semantics: `"0"`, `"false"`,
  `""`, `0` now disable the flag (previously any non-nil/false value enabled it,
  a privilege-escalation hazard with Rails checkbox conventions).
- **Method clobbering** across bitwise columns, against real database columns,
  or against the column itself now raises `ConfigurationError` at definition
  time instead of silently redefining accessors.
- **Mapping validation:** non-integer, negative, out-of-range (> 62), and
  duplicate bit positions, duplicate keys, and out-of-mapping defaults all raise
  `ConfigurationError` at definition time.
- **Integer assignment** (`roles = 33`) persists the integer verbatim, including
  its own unmapped bits; assigning `0` or `nil` now intentionally clears ghost
  bits.
- **`dup`** no longer copies the source record's unmapped bits.
- **`update_column`/`update_columns`** keep the raw cache in sync (no more stale
  forgotten-bit merges) and preserve ghost bits when given flag arrays.
- **NULL columns never resurrect defaults:** `deserialize(nil)` is always `[]`;
  defaults apply to new records only, so getters, scopes, and persistence agree.
- **Scopes are table-qualified**, fixing ambiguous-column SQL errors under joins.
- **`where`/`where.not`/`find_by` hash conditions** are now transparently
  serialized (exact-bitmask semantics, like Rails enum) instead of raising
  `NotSupportedError` — which also un-breaks uniqueness validators. Unknown flag
  values raise `UnknownValueError`.
- **Validator** no longer crashes on plain ActiveModel objects, honors the
  `:message` option, and truncates reflected invalid values (first 3, 64 chars
  each) to bound error/log output.
- **`Type#cast`** rejects `Hash`/`true`/`false` with `ArgumentError` and treats
  bare numeric strings as bitmasks, removing inconsistent garbage coercions.
- Subclassing deep-copies bitwise configuration (no shared mutable state between
  a parent and its subclasses), and re-extending `Model` on a subclass no longer
  wipes inherited definitions.

### Changed

- `activerecord` dependency corrected from `>= 5.0` to `>= 7.1, < 9` (the range
  the gem actually loads and is tested against).
- `BUGS.md`/`REQUIREMENTS.md` (internal development documents) are no longer
  shipped inside the packaged gem.
- Release workflow now gates on tests/lint/typecheck, validates the tag against
  `version.rb`, fails on a missing signing key, verifies the built gem is
  signed, and pins the credentials action to a commit SHA.
- CI now covers Ruby 3.2/3.3/3.4/4.0 plus an ActiveRecord 7.1/7.2/8.0 matrix.

### Documentation

- README rewritten for accuracy: correct atomic-removal SQL, documented hash
  condition serialization, corrected supported versions, documented boolean
  setter semantics, and removed incorrect claims (including the nonexistent
  `ActiveRecord::SerializationFailure`).

## [0.1.0] - 2026-05-21

### Added

- Initial release of the activerecord-bitwise gem.
- Bitmask arithmetic and operations for storing multiple boolean/enum values in a single integer column.
- Prefix and suffix options for generated helper methods.
- Database scopes: `with_`, `with_any_`, `with_exact_`, `without_`.
- High concurrency SQL atomic methods (`add_!`, `remove_!`) at class and instance levels.
- Graceful validation with `validates :attribute, bitwise: true`.
- A documented set of safety and architectural guarantees.
- Tapioca DSL compiler for Sorbet static analysis.
- SimpleCov AI integration for coverage reporting.
- Real-life usage simulation tests.
