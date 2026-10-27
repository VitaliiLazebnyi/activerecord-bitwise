# Contributing to activerecord-bitwise

Thanks for your interest in contributing! Bug reports and pull requests are
welcome on GitHub at <https://github.com/VitaliiLazebnyi/activerecord-bitwise>.

## Getting started

```bash
bundle install
```

## Before opening a pull request

Every gate below runs in CI and fails the build on any violation (no warnings-only mode).
The quality tooling needs Ruby 3.3+ (the Ruby 3.2 job only runs the test suite):

```bash
bundle exec rspec          # tests; 100% line AND branch coverage is enforced
bundle exec rake rubocop   # style (maximum strictness, all plugins)
bundle exec rake typecheck # Sorbet (lib/ is `typed: strict`)
bundle exec rake yard      # docs; must stay 100% documented
bundle exec rake reek flay # code smells and duplication
bundle exec rake audit     # bundler-audit: known vulnerabilities in dependencies
bundle exec rake mutant    # mutation testing; zero alive mutations (slow)
```

Or run everything except mutation testing with:

```bash
bundle exec rake
```

On pull requests CI mutates only the subjects you touched
(`bundle exec mutant run --since origin/main`); pushes to `main` run the full set.

To test against a specific ActiveRecord release:

```bash
AR_VERSION="~> 7.1.0" bundle install
AR_VERSION="~> 7.1.0" bundle exec rspec
```

## Guidelines

- Every behavioral fix needs a spec. Specs describe one behavior each
  (`describe` the unit, `context` the condition, `it` the expected outcome), assert
  exact values, and exercise the public API.
- Fix RuboCop, Reek and Flay findings in the code. Configuration relaxations and
  inline `# rubocop:disable` comments need a written justification.
- Treat bit mappings as append-only in examples and docs; never suggest
  re-indexing existing bit positions.
- The gem is `# typed: strict`: inside modules use `Kernel.raise` /
  `Kernel.Array` / `Kernel.lambda`, and add missing external constants to
  `sorbet/rbi/shims.rbi` rather than loosening the typed sigil.
- Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.

## Code of Conduct

Everyone interacting with this project is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
