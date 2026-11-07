# Contributing to `activerecord-bitwise`

Thanks for your interest in contributing! Bug reports and pull requests are
welcome on GitHub at <https://github.com/VitaliiLazebnyi/activerecord-bitwise>.

## Getting started

The repository develops on the Ruby in `.ruby-version`; Ruby 3.3 and newer are supported. `Gemfile.lock` is
committed: every single-version check installs exactly that bundle.

```bash
bundle install
git config core.hooksPath .githooks   # optional: run script/check --fast before every commit
```

## Before opening a pull request

Run every check CI runs on a pull request:

```bash
script/check          # or script/check --fast: everything except mutation testing and the outdated check
```

It installs the hash-pinned linters of `tools/requirements.txt` into `tmp/lint` and needs `python3` and
`gitleaks` on `PATH`. Ruby's verbose warnings are on (`RUBYOPT=-w -W:deprecated -W:performance`), as in CI. It
runs:

| Command                            | Gate                                                                                                   |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------ |
| `rake spec`                        | RSpec; 100% line **and** branch coverage, no pending or skipped examples, no Ruby warning              |
| `rake legacy_suite`                | the original spec suite of `main` (before the refactoring pass) passes against the current `lib/`      |
| `rake rubocop`                     | every cop of RuboCop and its plugins (`.rubocop.yml` explains each one that is off); no todo file      |
| `rake suppressions`                | no inline suppression or todo file of any tool (`script/forbidden_suppressions.sh`)                    |
| `rake typecheck`                   | Tapioca (the optional `:typecheck` group) generates the gem RBIs, then `srb tc` reports no error       |
| `rake yard`                        | YARD without a warning, 100% documented, a written description on every object                         |
| `rake reek flay flog debride`      | no code smell, no structural duplication, no method above a Flog score of 20, no method without caller |
| `rake audit`                       | bundler-audit: no locked gem with a known vulnerability                                                |
| `rake package`                     | `gem build --strict`, then the gem installs and loads from a clean `GEM_HOME`                          |
| `rake outdated`                    | every gem at its newest release, except the documented holds (`script/outdated_holds.yml`)             |
| `rake mutant`                      | mutation testing: every mutation is killed (`.mutant.yml`)                                             |
| `actionlint`, `zizmor`             | GitHub workflows (actionlint runs ShellCheck on every `run:` block; zizmor with the auditor persona)   |
| `shellcheck`, `shfmt`              | shell scripts: every optional ShellCheck check at style severity; shfmt reads `.editorconfig`          |
| `yamllint`, `rumdl`, `typos`, `ec` | YAML (every rule, strict), Markdown (every markdownlint rule), spelling, `.editorconfig`               |
| `gitleaks`                         | no secret in the history                                                                               |

Mutant parses the code with the `parser` gem, which only has a grammar for Ruby 3.3; run it on Ruby 3.3.13 (CI
does) to avoid the `parser/current` warning. Mutation runs are slow: while iterating, run one subject at a time,
e.g. `bundle exec mutant run 'ActiveRecord::Bitwise::Layout*'`.

CI also runs the suite on every supported Ruby, on every supported ActiveRecord minor and against PostgreSQL and
MySQL, each with its own bundle from `gemfiles/`:

```bash
BUNDLE_GEMFILE=gemfiles/activerecord_7_2.gemfile bundle install
BUNDLE_GEMFILE=gemfiles/activerecord_7_2.gemfile bundle exec rspec
BUNDLE_GEMFILE=gemfiles/postgresql.gemfile DATABASE_URL=postgresql://localhost/bitwise_test bundle exec rspec
```

## Rules

- **No inline suppressions.** Nothing may silence a linter, scanner, type checker, warning or test in
  place: no `rubocop:disable`, `:nocov:`, `:reek:`, `mutant:disable`, `gitleaks:allow`, `nosec`,
  `yamllint disable`, `rumdl-disable`, `T.unsafe`/`T.cast`/`T.bind`, `$VERBOSE = nil`, `skip`/`pending`/`focus`,
  and so on, and no todo or ignore file of any tool.
  Fix the cause. A rule that cannot apply to a file is configured narrowly in the tool's configuration
  file, with the reason written next to it.
- **No warnings.** Every workflow ends with a "Warning gate" job (`script/warning_gate.sh`) that fails
  the run when the log of any job contains a warning or a deprecation notice.
- **Least privilege in CI.** Every job declares its permissions, a timeout, and a `step-security/harden-runner`
  egress allow-list; every action is pinned to a commit SHA, and every dependency manifest is covered by
  Dependabot with a one-week cooldown.
- **Behavior is specified.** Every behavioral fix needs a regression spec, and every surviving mutant
  needs a test that kills it (or, when the mutation cannot change observable behavior, simpler code).
- Treat bit mappings as append-only in examples and docs; never suggest re-indexing existing bit
  positions.
- `lib/` and `script/` are `# typed: strict` (the files of `lib/` that reach `strong` stay there), and the spec
  helpers are at least `# typed: true`. Add missing external constants to `sorbet/rbi/shims.rbi` rather than
  loosening a typed sigil.
- Update `CHANGELOG.md` for user-visible changes.

## Code of Conduct

Everyone interacting with this project is expected to follow the
[Code of Conduct](CODE_OF_CONDUCT.md).
