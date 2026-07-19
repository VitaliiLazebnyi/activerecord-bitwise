# activerecord-bitwise — Deep Code Review & Empirical Test Report

**Reviewed commit:** `45ecba6` (branch `main`) · **Report date:** 2026-07-20
**Gem version in tree:** 0.1.0 · **Published on RubyGems:** 0.10.0 (see [P-1](#p-1))

## How this review was done

- **Static analysis:** 14 parallel specialist reviewers, each covering one dimension (type-casting, the `bitwise` macro, scope SQL, thread-safety, global monkey-patching, Sorbet typing, the validator, docs accuracy, tests, packaging/CI, Ruby idioms, security, config files, API design). They produced 292 raw observations.
- **Empirical verification:** every load-bearing claim was reproduced (or refuted) with runnable probes executed **inside Docker containers** — `ruby:3.2`, `ruby:3.3`, `ruby:3.4`, `ruby:4.0`, each with the gem's dependencies bundled — plus an ActiveRecord version matrix (6.1 → 8.1). All probe scripts and raw outputs are archived; decisive output is quoted inline below.
- Nothing in the repository was modified except the addition of this file.

Because the review was empirical, this report **separates confirmed defects from refuted claims**. Six findings that the static pass rated "high" did not survive testing; they are listed honestly in [§6](#6-refuted-or-downgraded-claims) so they are not mistaken for real bugs.

---

## 1. Executive summary

The gem is unusually **well-tooled on the surface**: 98 examples pass with 100% line + branch coverage on Ruby 3.2/3.3/3.4/4.0, RuboCop is clean, `srb tc` reports no errors, YARD is 100% documented, and the gem builds and installs. Those green checks are real and were reproduced.

Underneath, however, the review found **genuine, reproducible data-corruption and correctness bugs** — several of which silently violate the exact guarantees the README advertises. The most serious are not caught by the test suite because the suite tests the happy path and asserts on implementation details rather than persisted outcomes.

| Severity | Count (confirmed) | Headline examples |
|---|---|---|
| **High** | 7 | Infinite recursion on singular column names; atomic methods corrupt "forgotten bits"; `write_attribute`/`update_all` destroy unmapped bits; boolean setters treat `"0"`/`"false"` as true; silent method clobbering; mapping-value = bit-position with no validation |
| **Medium** | ~16 | Integer/`nil`/`0` assignment ghost-bit anomalies; `dup` copies ghost bits; where-guard bypasses & inconsistencies; NULL-column three-way divergence; ambiguous column under joins; false `activerecord >= 5.0` floor; validator crashes on plain ActiveModel |
| **Low / docs / packaging** | ~90 | 292-item long tail: marketing-hyperbole docs, stale cross-references, release-pipeline hygiene, Sorbet-is-theater, etc. |
| **Refuted / downgraded** | 6 | Thread-safety "crash", "uninstallable sorbet-runtime", "insert_all writes garbage", and 3 more — did **not** reproduce |

**Bottom line:** this is a gem whose polish (coverage %, lint, types, docs volume) substantially overstates its correctness. The array-of-flags abstraction leaks badly around every write path that isn't the one blessed generated setter, and the "forgotten bits" feature — the gem's central selling point — is destroyed by ordinary ActiveRecord idioms (`update_all`, `write_attribute`, the gem's own atomic `add_role!`). I would not deploy it as-is for anything touching authorization.

---

## 2. Verified-good (what genuinely passes)

These were confirmed by execution, not assumed:

- **Test suite:** `98 examples, 0 failures` on Ruby **3.2, 3.3, 3.4, 4.0**; **100.0% line (449/449) and branch (175/175)** coverage.
- **Static tooling:** `rubocop` → "no offenses" (16 files); `srb tc` → "No errors"; `yard stats` → "100.00% documented"; `gem build` → succeeds (one benign open-ended-dependency warning).
- **Most README examples are accurate.** A verbatim transcription of the README's runnable snippets passed, including the subtle ones: `roles = ['', 'admin', 'author'] # => [:admin, :author]`, `roles_changed?`/`roles_was`, and even `roles_before_type_cast # => 5` (accurate *after* save — see [§6 R-4](#r-4)).
- **Dirty tracking works.** `changes`, `saved_change_to_roles`, `previous_changes` behave correctly, and an identical reassignment (`u.roles = u.roles`) is correctly **not** marked changed.
- **STI mapping isolation in memory** holds: sibling subclasses keep distinct mappings; the after_initialize validation callback is registered exactly once across the hierarchy.
- **`Marshal` round-trip and `clone`** preserve the flag array.
- **`update_column` / `insert_all` correctly serialize** array input through the Type, and the 100-element cap fires even there (contradicting a static claim — see [§6 R-3](#r-3)).
- **SQL injection surface is clean:** column names go through `quote_column_name`, masks/ids are bind parameters. No injection reproduced.

---

## 3. Confirmed HIGH-severity defects

### H-1 · Infinite recursion (`SystemStackError`) when the column name is singular or uncountable

**File:** `lib/active_record/bitwise.rb:500-542`

For a column named `roles`, `singular_col = "role"`, so the gem defines instance method `add_role!` (the implementation) and `add_roles!` (an alias that calls `add_role!`). But when the column name is **already singular or uncountable** — `:status`, `:access`, `:fish`, `:series` — `singularize` returns the name unchanged, so the alias and the implementation are the **same method name**. The alias definition (line 519-521) overwrites the implementation, leaving a method that calls itself.

```
--- B1 bitwise :status (singular==plural)
SystemStackError: infinite recursion CONFIRMED
--- B2 bitwise :fish (uncountable)
SystemStackError: infinite recursion CONFIRMED
```

Any app with a bitwise column named with a singular/uncountable noun gets a stack overflow the first time it calls the instance-level atomic method. `:status` in particular is an extremely common column name. Not covered by any test.

---

### H-2 · Instance atomic methods (`add_role!`/`remove_role!`) corrupt "forgotten bits" by poisoning the raw cache

**File:** `lib/active_record/bitwise.rb:502-517, 523-538`

After the atomic SQL `UPDATE`, the method reads the value back with `pluck` and stores it into `@_bitwise_raw_values[:roles]`. That cache is contractually an **Integer** (the raw DB bitmask used to reconstruct unmapped bits on the next serialize). But the value written back is a **deserialized Array**:

```
--- A7 ghost bit 16 planted; add_role!(:admin); inspect cache; then roles=[:editor]; save
raw after add: 17; cache[:roles] = [:admin] (Array)      # <-- should be integer 17
raw after save: 4 (ghost-preserving: 20, wiped: 4)        # <-- ghost bit 16 destroyed
```

On the subsequent in-memory `save`, `serialize` calls `.to_i` on that Array (→ `0`), so `(0 & ~known_mask) | new_mask` **wipes every unmapped bit**. The gem's headline "non-destructive forgotten bits" guarantee is broken by its *own* atomic API. The regression test for BUG-THREAD-001 only asserts that `transaction`/`lock` were *called*, so it never notices.

---

### H-3 · `write_attribute` / `record[:col] = …` then `save` silently destroys forgotten bits

**File:** `lib/active_record/bitwise.rb:71-101` (`cast`), `154-181` (`serialize`)

`cast` only attaches `@_bitwise_raw_value` when the *input array already carried it*. The generated setter stamps the ivar (line 393-398), but `write_attribute` and `record[:roles] = …` **bypass the setter**. The stored array has no ivar, so `serialize` falls back to raw `0` and clears all unmapped bits:

```
--- A1 ghost bit 16 planted; u[:roles] = [:author]; save
raw after save: 2   (ghost-preserving intent: 18, actual: 2 — bit 16 destroyed)
```

`write_attribute`/`[]=` are completely ordinary ActiveRecord idioms; nothing warns the developer. The README documents ghost-bit loss only across background-job serialization, never for in-process attribute writes.

---

### H-4 · `update_all` destroys forgotten bits, and zeroes the whole column on invalid input

**File:** `lib/active_record/bitwise.rb:193-211` (`RelationExtension#update_all`)

The `update_all` interception serializes through an **ivar-less `cast`**, so it wipes forgotten bits for **every matched row**:

```
--- A5 ghost bit 16 planted; User.where(id:).update_all(roles: [:author])
raw: 2   (ghost-preserving: 18, actual: 2)
```

Worse, when the value array contains only **unrecognized** values, the serialized mask is `0` and the interception issues `SET roles = 0` — silently **zeroing the column table-wide** with no error:

```
--- A6 User.where(id:).update_all(roles: [:bogus])
raw: 0   (was 5)
```

A typo in a batch update (`update_all(roles: [:administrator])` instead of `:admin`) silently clears the column for every matched row. This is inconsistent with the instance path (which preserves) and with the `where` guard (which *blocks* hash queries but *rewrites* `update_all`).

---

### H-5 · Boolean flag setters treat `"0"`, `"false"`, and `""` as **true**

**File:** `lib/active_record/bitwise.rb:437-449`

The generated `flag=` setter uses raw Ruby truthiness (`if val`), so every non-`nil`/non-`false` value enables the flag — including the exact strings HTML forms submit for *unchecked* boxes:

```
--- B4 boolean setter with various values
admin = "0"     -> admin? true     # <-- form "off" value enables the flag
admin = "false" -> admin? true     # <--
admin = ""      -> admin? true     # <--
admin = 0       -> admin? true
admin = false   -> admin? false
admin = nil     -> admin? false
```

The README explicitly pitches form/checkbox usage. A checkbox submitting `"0"` when unchecked (Rails' own `hidden_field` convention for checkboxes) will **set** the flag. For a permissions/roles gem this is a privilege-escalation-shaped bug. Rails' native `enum` and `ActiveModel::Type::Boolean` both map `"0"`/`"false"` to false; this gem does not.

---

### H-6 · Silent cross-column / column-name method clobbering

**File:** `lib/active_record/bitwise.rb:416-430` (collision guard)

The collision guard only checks against `ActiveRecord::Base` instance methods. It misses (a) two bitwise columns generating the same accessor, and (b) a mapping key equal to a real DB column:

```
--- B3 two columns, same mapping key :admin, no prefix/suffix
after admin=true: roles=[] permissions=[:admin]    # last definition wins; roles' :admin flag is unreachable

--- B8 mapping key :name equal to a real 'name' column
k.name = 'x'; k.name? -> true; column value: nil; roles: [:name]   # flag accessor shadows the real column
```

The flag accessor silently shadows the real column writer, so `k.name = 'x'` no longer sets the `name` column — it toggles a bitwise flag. No warning at definition or runtime.

---

### H-7 · Mapping values are bit **positions**, not masks, and receive **no validation**

**File:** `lib/active_record/bitwise.rb:313-320` (normalization), `154-181` (serialize)

`{admin: 0, author: 1, editor: 2}` means positions 0/1/2. A developer thinking in masks who writes `{admin: 1, author: 2, editor: 4}` silently gets positions 1/2/4 (a hole at bit 0, editor at bit 4). Nothing validates the values:

```
--- B5a mapping {a: -1}   -> 1 << -1 == 0, silent dead flag; saving [:a] persists raw 0
--- B5b mapping {a: 1, b: 1}  -> duplicate position; assigning [:a] reads back [:a, :b] (aliased)
--- B5c mapping {a: "3"}  -> "3".to_i => bit 3 (works by accident)
         mapping {a: "abc"} -> "abc".to_i => 0 => bit 0 collision
--- B5d mapping {a: :b}   -> RAISED NoMethodError: undefined method `to_i' for a Symbol
```

Duplicate positions silently alias flags (a correctness landmine for permissions), negative positions create silently dead flags, non-numeric string values collide at bit 0, and Symbol values crash at class-definition time. The README's own advice ("bit shift position") is the only guardrail, and it is easy to misread.

---

## 4. Confirmed MEDIUM-severity defects

Each was reproduced; evidence abbreviated.

| # | File:line | Defect | Evidence |
|---|---|---|---|
| M-1 | bitwise.rb:389-400 | **Integer assignment discards the integer's own unknown bits.** `u.roles = 33` (bit 0 known + bit 5 unknown) persists `1`. Setter overwrites the fresh ivar from `deserialize(33)` with the stale cached raw. | `A2: in-memory [:admin]; raw 1` |
| M-2 | bitwise.rb:389, 114-123 | **`roles = 0` / `roles = nil` cannot clear ghost bits.** `= 0` keeps the ghost bit; `= nil` resurrects the default and persists NULL. | `A3: raw 16`; `D2: getter [:admin], DB nil` |
| M-3 | bitwise.rb:687-690 | **`dup` copies ghost bits.** `initialize_dup` clears the cache, but `dup` copies `*_before_type_cast`, so the raw value repopulates and the duplicate persists the original's unmapped bits. | `A8: dup raw 17` (expected 1) |
| M-4 | bitwise.rb:343-352 | **Stale raw cache after `update_column`/`touch`** (callback-less). A later flag setter + `save` merges outdated forgotten bits. | `A4: raw 2` (expected 34) |
| M-5 | bitwise.rb:502-517 | **Outer-transaction rollback diverges memory from DB.** `add_role!` writes in-memory state inside its own transaction; an outer `Rollback` reverts the DB but leaves the record showing the value with `changed? == false`. | `A10: DB 0, in-memory [:admin], changed? false` |
| M-6 | bitwise.rb:220-240 | **`where`-guard is inconsistent and trivially bypassed.** Blocks `where(roles:)`, `find_by`, `find_or_create_by`, `where.not`; passes through `where(users: {roles: 1})`, `where("roles = 1")`, `where!(roles: 1)`, `rewhere(roles: 1)`. Blocking `find_by` also blocks the uniqueness validator's own lookup. | `C6` table; `C7` uniqueness → `RecordInvalid` |
| M-7 | bitwise.rb:114-123 | **NULL column + type default = three-way divergence.** Getter shows `[:admin]`, `with_roles(:admin)` does **not** match the row, and an unrelated save leaves the DB `NULL`. | `D1` |
| M-8 | bitwise.rb:549-604 | **Scopes use unqualified column names → ambiguous-column SQL error under joins.** | `C8: SQLite3::SQLException: ambiguous column name: roles` |
| M-9 | bitwise.rb:502-517 | **Atomic add/remove on an unsaved record** silently no-ops the DB and resets the in-memory value to `[]` with `changed? == false`. | `D4: in-memory []` |
| M-10 | bitwise.rb:324, 700-702 | **Subclass state hazards.** A subclass calling `extend ActiveRecord::Bitwise::Model` re-runs `class_attribute` and **wipes inherited definitions**; parent/child share the same per-column config Hash object by reference. | `B6: Child2 defs []`; `B7: share same Hash: true` |
| M-11 | bitwise.rb:114-123 | **Default with an unmapped key diverges** between new records (`[:admin, "bogus"]`) and NULL rows (`[:admin]`). | `D3` |
| M-12 | bitwise_validator.rb:11-15 | **Validator crashes on plain ActiveModel** (`sig` demands `ActiveRecord::Base`) and **ignores the `message:` option**. | `D6: TypeError`; `D5: message: ignored` |
| M-13 | bitwise.rb:84-91 | **`cast` of Hash/`true`/numeric-string produces garbage.** `cast({a:1}) => ["[:a, 1]"]`, `cast(true) => ["true"]`, `cast("5") => ["5"]` (unknown flag) while `cast(5) => [:admin]` (bitmask) — inconsistent coercion, and saving then clears known flags. | `D8` |
| M-14 | gemspec:38 | **`activerecord >= 5.0` is false.** See AR matrix below: AR ≤ 7.0 will not even load with the gem's deps; the real working range is 7.1 / 7.2 / 8.x. README's "Rails 5.0+" is impossible alongside Ruby ≥ 3.2. | `ar_matrix.txt` |
| M-15 | bitwise.rb:114-116 | **`deserialize(nil)` with no default returns a mutable, ivar-less array**, breaking the frozen+raw-ivar invariant every other path upholds. | `D7: frozen false, ivar false` |
| M-16 | bitwise.rb:82 | **100-element cap raises at inconsistent times** — at assignment via the setter, but only at first read via `write_attribute`. | `D9` |

### ActiveRecord version matrix (Ruby 3.3, in Docker)

| ActiveRecord | Result |
|---|---|
| ~> 6.1 | ❌ fails to load (`NameError` requiring active_record) |
| ~> 7.0 | ❌ `LoadError` — AR 7.0 pins `sqlite3 ~> 1.4`, gem dev-dep wants `~> 2.1` |
| ~> 7.1 | ✅ 98 examples, 0 failures |
| ~> 7.2 | ✅ passes (a one-off failure was the order-dependent spec, [T-1](#appendix-b)) |
| ~> 8.0 | ✅ 98 examples, 0 failures |
| 8.1 (default) | ✅ 98 examples, 0 failures |

The gemspec should declare roughly `activerecord >= 7.1` (and add a `< 9` ceiling given it monkey-patches AR internals). `class_attribute ... default:` alone already requires ActiveSupport ≥ 5.2.

---

## 5. Low-severity, documentation, and packaging findings

The full 292-item catalog is preserved; the substantive long-tail items, grouped:

**Documentation accuracy**
- **D-1 · README `remove_role!` SQL is wrong.** README claims `roles & ~2`; actual SQL is `roles = COALESCE(roles,0) - (COALESCE(roles,0) & 4)` (subtraction form, and mask 4 not 2 for the example's `:author`). Confirmed via SQL capture.
- **D-2 · The `where`/`where.not`/`find_by` NotSupportedError behavior is undocumented in the README.** Adopters will be shocked that `User.where(roles: 1)` raises deep in production. This is a major behavior change to a core AR API with no user-facing docs.
- **D-3 · "17 safety guarantees" mismatch.** CHANGELOG says 17; REQ-007 lists 16; the README section that described them was deleted in commit `e1cff1c` but CHANGELOG/REQUIREMENTS still reference it.
- **D-4 · `BUG-DOC-002` claims `.env.example` exists** — it was created then deleted (commit `e1cff1c`); BUGS.md is stale. `.gitignore` also never ignored `.env`.
- **D-5 · `BUG-CI-002` claims README was set to "Rails 7.0+"** — the README actually says "Rails 5.0+" (and elsewhere the gem claims 5.0). Internal contradiction.
- **D-6 · Capacity Note contains sloppy/false technical claims** (two's-complement "violently corrupts," "SQLite strictly coerces outputs to Strings"), and pervasive marketing hyperbole ("violently," "organically," "natively") throughout. Typos: "native native," "will suddenly evaluation as," literal `\\times` in the `$O(N \times V)$` markup.
- **D-7 · README references a nonexistent `ActiveRecord::SerializationFailure`.**

**Packaging / release engineering**
- <a id="p-1"></a>**P-1 · A stray `v0.10.0` git tag** (typo of `v0.1.0`) sits on the same commit as `v0.1.0`, and **RubyGems shows `activerecord-bitwise (0.10.0)` as the published version** while `version.rb` still says `0.1.0`. The tag-driven release workflow (`sed` rewrites `version.rb` from the tag, no commit-back) published `0.10.0`, permanently shadowing future `0.1.x`/`0.2.x` releases in the resolver.
- **P-2 · Internal dev docs shipped in the gem.** `spec.files` ships `BUGS.md` and `REQUIREMENTS.md` (the internal bug ledger and requirements) to every consumer. Confirmed by unpacking the built `.gem`.
- **P-3 · Release workflow has no test/lint/typecheck gate** — `release.yml` builds and `gem push`es on tag with no `rspec`/`rubocop`/`srb` run first. A broken tagged commit ships.
- **P-4 · Supply-chain: `rubygems/configure-rubygems-credentials@main`** is pinned to a mutable ref on the credential-handling step. Pin to a SHA/tag.
- **P-5 · Release `$VERSION` is derived from the git tag and used unquoted** in `sed -i "s/…/$VERSION/"` and `gem push …-$VERSION.gem`. A crafted tag name is an injection vector (mitigated only by "tag pushers are maintainers").
- **P-6 · Silent unsigned releases.** Signing key is used only `if File.exist?(...) && File.size > 100`; a missing/empty `GEM_PRIVATE_KEY` secret yields an unsigned gem with no failure. The signing cert is self-signed with a 10-year window (2026-04-15 → 2036-04-12); subject email matches the gemspec.
- **P-7 · CI has no ActiveRecord matrix** (only newest resolvable AR) and skips Ruby 3.4; `.ruby-version` (3.3.0) diverges from the CI static jobs (4.0). No `Gemfile.lock` (non-reproducible CI, an intentional-but-noted tradeoff for a gem). No `Rakefile`, `CONTRIBUTING`, `CODE_OF_CONDUCT`, `SECURITY.md`, or Dependabot config.

**Ruby / design quality**
- **Q-1 · `Model#bitwise` is a single ~382-line method** doing normalization, attribute registration, and defining ~10 method families and 4 scopes inline, with large verbatim-duplicated blocks (getter/setter cache hydration; add/remove singular pairs; mask-building ×4).
- **Q-2 · Sorbet `# typed: strict` is largely theater** — ~128 `T.unsafe` calls erase the checking at nearly every call site, and `T.unsafe(self)` is invoked 6+ times per attribute read inside the metaprogrammed accessors (small but real per-read cost). No gem RBIs ship.
- **Q-3 · Raw-value smuggling via `instance_variable_set` on Array objects** is fragile by design (this is BUG-IVAR-001, "mitigated" = documented). It is the root cause of H-2/H-3/H-4/M-1..M-4.
- **Q-4 · Pervasive `Kernel.raise`/`Kernel.Array`/`Kernel.lambda`** prefixes (Sorbet-strict artifacts) are unidiomatic; user-facing failures raise bare `ArgumentError` instead of the gem's `Error` hierarchy.
- **Q-5 · `bitwise_schema` returns the live internal mapping hash** (mutable) and is redundantly redefined on every `bitwise` call.
- **Q-6 · The `with_` scope's empty-args branch has a dead `quote_column_name` expression** (bitwise.rb:551) whose only effect is checking out a DB connection for nothing — plausibly written to satisfy branch coverage.
- **Q-7 · Global injection with no opt-in/opt-out:** `bitwise` and `bitwise_definitions` are forced onto `ActiveRecord::Base`, and `RelationExtension`/`WhereChainExtension` are prepended app-wide. `WhereChainExtension#not` reaches into Rails' private `@scope` ivar.

**Security (beyond the confirmed items)**
- **S-1 · Validator reflects unbounded, unsanitized user input** into the error message (`invalid_values.join(', ')`, up to 100 arbitrary-length strings) — output/log-injection and amplification surface.
- **S-2 · Forged-ivar bit smuggling** (curiosity): an Array carrying a crafted `@_bitwise_raw_value` passed to `update_all` has its bits OR'd into storage (`A9: forged 255 → persisted 249`). Not reachable from ordinary Rails params (which are plain arrays), but reachable via `Marshal`/hand-crafted input.

---

## 6. Refuted or downgraded claims

Honesty matters more than a big number. These were flagged by the static pass but **did not survive empirical testing**:

- <a id="r-1"></a>**R-1 · "`@deserializing_depth` is a shared counter that crashes under concurrency" (rated high ×5) — REFUTED on MRI.** 8 threads × 20 000 `deserialize(nil)`-with-default and 8 × 50 000 `deserialize(5)` produced **0 thread deaths**, and the counter returned to `0`. MRI's GIL serializes the non-yielding integer path, so the check-then-increment never interleaves. It remains a genuine *code smell* and a **theoretical** risk on non-GIL runtimes (JRuby/TruffleRuby) plus a narrow async-exception window (the `+= 1` sits *outside* the `begin/ensure` at bitwise.rb:112-113, so a `Timeout` there could leak the counter). **Downgraded to low.**
- **R-2 · "`sorbet-runtime ~> 0.6` matches no published version / gem is uninstallable" (rated high ×3) — REFUTED.** It resolves to `sorbet-runtime 0.6.13342` and the gem installs and boots. Sorbet genuinely publishes `0.6.x`. (The dev `sorbet ~> 0.5` vs runtime `~> 0.6` split is still an inconsistency worth aligning, but nothing breaks.)
- <a id="r-3"></a>**R-3 · "`insert_all`/`update_column` write garbage / bypass serialization" — REFUTED.** Both correctly serialize array input through the Type (`C9/C10: raw 1`), and the 100-element DoS cap even fires inside `insert_all` (`C11: ArgumentError`).
- <a id="r-4"></a>**R-4 · "README's `roles_before_type_cast # => 5` is wrong" — REFUTED.** It is accurate after the `admin!` save the example performs (`E: MATCH actual=5`).
- **R-5 · "Unknown cop `Style/OneClassPerFile` in `.rubocop.yml`" — REFUTED.** The cop resolves in RuboCop 1.88 (`--show-cops` lists it; a targeted run is clean). Not an error.
- **R-6 · "100-element cap is bypassable via write paths" — largely REFUTED** (see R-3). The cap holds on setter, `write_attribute` (at read), and `insert_all`.

---

## Appendix A — reproduction environment

All probes ran in Docker (`ruby:3.3` base with the gem's `Gemfile.lock` resolved: `activerecord 8.1.3`, `sqlite3 2.9.5`, `sorbet-runtime 0.6.13342`, `rspec 3.13`, `rubocop 1.88`, `yard 0.9.45`). Baseline suite additionally verified on `ruby:3.2`, `ruby:3.4`, `ruby:4.0`. Probe scripts are archived under the review scratchpad (`a_ghost_bits.rb`, `b_naming_macro.rb`, `c_scopes.rb`, `d_defaults_validator.rb`, `e_readme.rb`, `f_threads.rb`, `g_sti_dirty.rb`, `h_perf.rb`).

## Appendix B — cross-cutting test-suite observations

- <a id="appendix-b"></a>**T-1 · Order-dependent example.** The `[:validated]`-flag expectation passes only if another example instantiated the model first; under some random seeds it fails in isolation (observed once on the AR 7.2 run). The suite leaks class-level state between examples.
- **T-2 · Coverage is genuine (100%) but partly gamed.** A 166-line "extra coverage" mega-example exists to reach branches (e.g. the dead `with_` connection-checkout at bitwise.rb:551), and several "guarantee" examples assert on message-expectations / internal flags rather than persisted outcomes — which is exactly why H-2, H-3, and H-4 (all persisted-data bugs) pass CI.
- **T-3 · Concurrency "guarantees" are not tested concurrently in a meaningful way** — `FOR UPDATE`/`lock(true)` is a no-op on the SQLite test DB, so the credited BUG-THREAD-001 "fix" is never actually exercised.

## Appendix C — performance (informational)

Measured in-container (20 000 iterations; SQLite `:memory:`):

- Global `where`-interception overhead: **~1.4 µs/call** (53.4 vs 52.0 µs) — ~2–3%, paid by *every* model in the host app.
- `Type#deserialize` Sorbet sig-check overhead: **~0.08 µs/call** (0.48 with checking vs 0.40 with `checked_level = :never`) — modest per call, but this runs once per row per query.

These are small in absolute terms; the earlier static concern about hot-path Sorbet cost is real but minor. Reported for completeness, not as a defect.
