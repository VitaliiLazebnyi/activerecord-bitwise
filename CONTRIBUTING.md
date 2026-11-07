# Contributing to activerecord-bitwise

Thanks for your interest in contributing! Bug reports and pull requests are
welcome on GitHub at <https://github.com/VitaliiLazebnyi/activerecord-bitwise>.

## Getting started

The repository develops on the Ruby in `.ruby-version`; Ruby 3.3 and newer are supported.

```bash
bundle install
git config core.hooksPath .githooks   # optional: run the fast gates before every commit
```

## Before opening a pull request

Run the verification suite. Every gate is enforced in CI and fails the build:

```bash
bundle exec rake
```

That runs, in order:

| Task | Gate |
| --- | --- |
| `rake spec` | RSpec; 100% line **and** branch coverage, no pending or skipped examples, no Ruby warning from `lib/` or `spec/` |
| `rake legacy_suite` | the original spec suite of `main` (before the test and refactoring pass) passes against the current `lib/` (`script/legacy_suite.rb`) |
| `rake rubocop` | RuboCop with its plugins (`.rubocop.yml`); no todo file, no exclusions for new code |
| `rake suppressions` | no inline suppression anywhere (`script/forbidden_suppressions.sh`, see below) |
| `rake typecheck` | Tapioca generates the gem RBIs (from `typecheck.gemfile`), then `srb tc` must report no errors |
| `rake yard` | YARD must report 100% documented |
| `rake reek` / `rake flay` | no code smell (default Reek configuration) and no structural duplication |
| `rake audit` | bundler-audit: no dependency with a known vulnerability |

Not part of the default task, but also enforced in CI:

```bash
bundle exec rake mutant     # mutation testing; every mutation must be killed (see .mutant.yml)
bundle exec rake outdated   # every gem at its newest release, except the documented holds
gem build activerecord-bitwise.gemspec
```

Mutant parses the code with the `parser` gem, which only has a grammar for Ruby 3.3; run it on Ruby
3.3.13 (CI does) to avoid the `parser/current` warning. Mutation runs are slow: while iterating, run one
subject at a time, e.g. `bundle exec mutant run 'ActiveRecord::Bitwise::Layout*'`.

To test against a specific ActiveRecord release:

```bash
AR_VERSION="~> 7.2.0" bundle update activerecord
AR_VERSION="~> 7.2.0" bundle exec rspec
```

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type checker, warning or test in
  place: no `rubocop:disable`, `:nocov:`, `:reek:`, `mutant:disable`, `gitleaks:allow`, `nosec`,
  `T.unsafe`/`T.cast`/`T.bind` in `lib/`, `$VERBOSE = nil`, `skip`/`pending`/`focus`, and so on.
  Fix the cause. A rule that cannot apply to a file is configured narrowly in the tool's configuration
  file, with the reason written next to it.
- **No warnings.** Every workflow ends with a "Warning gate" job (`script/warning_gate.sh`) that fails
  the run when the log of any job contains a warning or a deprecation notice.
- **Behavior is specified.** Every behavioral fix needs a regression spec, and every surviving mutant
  needs a test that kills it (or, when the mutation cannot change observable behavior, simpler code).
- Treat bit mappings as append-only in examples and docs; never suggest re-indexing existing bit
  positions.
- `lib/` is `# typed: strict`. Add missing external constants to `sorbet/rbi/shims.rbi` rather than
  loosening the typed sigil.
- Update `CHANGELOG.md` for user-visible changes.

## Code of Conduct

Everyone interacting with this project is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
