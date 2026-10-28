# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Internal refactor of `lib/` into small single-purpose modules (types, mapping,
  collisions, definers, instance-method concerns). Public behavior is unchanged.
- Development dependencies upgraded to their latest releases (SimpleCov 1.x,
  rubocop-md 2.x, ...); the repository now targets Ruby 4.0.6 (`.ruby-version`) while the
  gem still supports Ruby 3.2+ and ActiveRecord 7.1 to 8.x.
- Quality tooling moved from the gemspec into the Gemfile's `:quality` group (Ruby 3.3+).

### Added

- Mutation testing (mutant), Reek, Flay, bundler-audit, CodeQL (security-extended and
  security-and-quality), dependency review, gitleaks, OpenSSF Scorecard, actionlint and
  zizmor; all CI actions are pinned to commit SHAs with least-privilege permissions.

### Removed

- The per-record raw bitmask cache and the `after_save` callback that reset it: the raw
  bitmask is derived from the attribute's value before type cast on demand, so nothing can go
  stale. `clear_bitwise_raw_values_cache!` remains as a no-op for compatibility.
- The class-level "columns validated" memo flag and the `reload` override that existed only to
  reset the cache; each definition now records its own `validated` state.
- Two unreachable defensive branches (`Type#deserialize` "Casting failed" guard and the
  non-Hash/Array mapping guard, which Sorbet's signature already rejects) and the unused
  internal `#_bitwise_coerce_raw`.

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
