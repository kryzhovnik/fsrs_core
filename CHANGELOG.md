# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-06-28

### Added

- Initial release: a faithful pure-Ruby implementation of the FSRS-6 spaced-repetition
  scheduler core, ported from and golden-tested against the Rust `fsrs` crate `6.6.1`.
- `FsrsCore::Scheduler` with `next_states`, `next_state`, `next_interval`, `memory_state`,
  and `current_retrievability`.
- `Data` value objects (`MemoryState`, `ItemState`, `NextStates`, `Review`), strict input
  validation, and the `FsrsCore::Error` / `ValidationError` / `InvalidParametersError` hierarchy.
- Default FSRS-6 parameters and per-index clamp ranges, verbatim from `fsrs 6.6.1`.
- Differential oracle that verifies 4,096 deterministic cases against the pinned Rust
  `fsrs 6.6.1` reference (`rake oracle`).

[0.1.0]: https://github.com/kryzhovnik/fsrs_core/releases/tag/v0.1.0
