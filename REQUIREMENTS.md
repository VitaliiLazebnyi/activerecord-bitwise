# Active Specifications

| ID | Description |
|---|---|
| AR_BITWISE-REQ-001 | Feature must allow saving multiple symbols to integer via bitwise masking logic. |
| AR_BITWISE-REQ-002 | System must be Ruby 3.2+ and Rails 5.0+ compatible. |
| AR_BITWISE-REQ-003 | Model Configuration must support Prefix and Suffix options for generated helper methods. |
| AR_BITWISE-REQ-004 | Database Scopes must include `with_`, `with_any_`, `with_exact_`, and `without_` prefixes with fuzzer immunization and zero-bounds. |
| AR_BITWISE-REQ-005 | High Concurrency SQL atomic methods must be provided at class and instance levels. |
| AR_BITWISE-REQ-006 | Graceful Validation with safe assignment and custom `validates ..., bitwise: true` must be supported. |
| AR_BITWISE-REQ-007 | Gem must provide 17 detailed Safety Guarantees (forgotten bits, STI isolation, fuzzer immunization, nil db coalescence, symbol DoS prevention, frozen arrays, column type check, where clause poisoning defense, boot-deadlock trap, lifecycle bricking prevention, clone bleeding prevention, zero-state scope bounds, multi-tenant ETL schema, SQLite string coercion, update_all, over-shift execution halt). |
| AR_BITWISE-REQ-008 | System must install and configure `simplecov-ai` to generate a concise AST-mapped Markdown digest at `coverage/ai_report.md` alongside the standard SimpleCov HTML reports. |
| AR_BITWISE-REQ-009 | Gem must have comprehensive real-life usage simulation tests (high-concurrency race condition defense, ETL/analytics data pipeline integration, dynamic multi-tenant form validation and processing). |

## [ARCHIVED]
_No archived requirements yet._
