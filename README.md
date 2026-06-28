# fsrs_core

Pure-Ruby implementation of the **FSRS-6** spaced-repetition scheduler core, ported verbatim from and
golden-tested against the Rust `fsrs` crate `6.6.1`. Module `FsrsCore`.

## Scope (v0.1)

Scheduler core only: `next_states`, `next_state`, `next_interval`, `memory_state`,
`current_retrievability`, plus `Data` value objects, validation, and the `FsrsCore::Error` hierarchy.
No optimizer, no learning-steps. Intervals are returned **raw** (real-valued days) — the caller
rounds, floors at 1, and applies any `maximum_interval`.

## Versions

|  gem  | algorithm | crate oracle |
|-------|-----------|--------------|
| 0.1.0 |   FSRS-6  | `fsrs 6.6.1` |

## Usage

```ruby
require "fsrs_core"

sched = FsrsCore::Scheduler.new
ns = sched.next_states(memory_state: nil, desired_retention: 0.9, days_elapsed: 0)
ns.good.interval            # => Float (raw days)
sched.next_state(memory_state: nil, desired_retention: 0.9, days_elapsed: 0, rating: 3)
sched.next_interval(stability: 21.4, desired_retention: 0.9)
sched.memory_state(reviews: [FsrsCore::Review.new(rating: 3, delta_t: 0)])
sched.current_retrievability(memory_state: FsrsCore::MemoryState.new(stability: 10.0, difficulty: 5.0), days_elapsed: 2.5)
```

## Precision & attribution

Computation is f64; the crate oracle is f32 — golden tests match within tight per-result-type
tolerances. This gem is a port of the FSRS-6 scheduler from the BSD-3-Clause `fsrs` crate; see
`THIRD_PARTY_NOTICES`.

## Regenerating golden vectors (needs cargo, dev machine only)

```bash
cd test/support/golden_gen && cargo run --locked > ../golden.json
```
No Rust is needed to use the gem or run the ordinary Ruby suite — `golden.json` is committed.

## Tests

The normal suite is fast and does not require Rust:

```bash
rake test
```

The full differential check generates 4,096 deterministic cases and compares this gem with the
pinned Rust `fsrs 6.6.1` oracle. It requires Cargo but does not keep the generated corpus:

```bash
bundle exec rake oracle
```

Successful output confirms full conformance and reports, per metric, the largest deviation from Rust
alongside the minimal tolerance it stays within. To include raw absolute and relative deltas for
troubleshooting, enable verbose output:

```bash
ORACLE_VERBOSE=1 bundle exec rake oracle
```
