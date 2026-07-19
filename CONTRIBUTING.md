# Contributing to activerecord-bitwise

Thanks for your interest in contributing! Bug reports and pull requests are
welcome on GitHub at <https://github.com/VitaliiLazebnyi/activerecord-bitwise>.

## Getting started

```bash
bundle install
```

## Before opening a pull request

Run the full verification suite (all four gates are enforced in CI):

```bash
bundle exec rspec     # tests; 100% line AND branch coverage is enforced
bundle exec rubocop   # style
bundle exec srb tc    # Sorbet type checking
bundle exec yard stats --list-undoc  # docs; must stay 100% documented
```

Or simply:

```bash
bundle exec rake
```

To test against a specific ActiveRecord release:

```bash
AR_VERSION="~> 7.1.0" bundle install
AR_VERSION="~> 7.1.0" bundle exec rspec
```

## Guidelines

- Every behavioral fix needs a regression spec (see
  `spec/activerecord_bitwise_regression_spec.rb` for the pattern).
- Treat bit mappings as append-only in examples and docs; never suggest
  re-indexing existing bit positions.
- The gem is `# typed: strict`: inside modules use `Kernel.raise` /
  `Kernel.Array` / `Kernel.lambda`, and add missing external constants to
  `sorbet/rbi/shims.rbi` rather than loosening the typed sigil.
- Update `CHANGELOG.md` under `[Unreleased]` for user-visible changes.

## Code of Conduct

Everyone interacting with this project is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
