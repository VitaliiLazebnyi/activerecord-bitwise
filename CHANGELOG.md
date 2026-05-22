# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-05-21

### Added

- Initial release of the activerecord-bitwise gem.
- Bitmask arithmetic and operations for storing multiple boolean/enum values in a single integer column.
- Prefix and suffix options for generated helper methods.
- Database scopes: `with_`, `with_any_`, `with_exact_`, `without_`.
- High concurrency SQL atomic methods (`add_!`, `remove_!`) at class and instance levels.
- Graceful validation with `validates :attribute, bitwise: true`.
- 17 safety and architectural guarantees.
- Tapioca DSL compiler for Sorbet static analysis.
- SimpleCov AI integration for coverage reporting.
- Real-life usage simulation tests.
