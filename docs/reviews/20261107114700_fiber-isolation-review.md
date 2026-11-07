# Fiber isolation review

## Participants

Andrei Makarov (@amkisko)

## Decisions

No gem-level Fiber switch. Request DB timings already use `ActiveSupport::IsolatedExecutionState` on Rails 7.1+ (fallback `Thread.current` on Rails 7.0). Fiber isolation is therefore configurable only via the host Rails `config.active_support.isolation_level` (or `IsolatedExecutionState.isolation_level`). Adding a parallel gem API would duplicate Rails state.

Add maintainer fiber load series (`SCENARIO=fiber` / `make bench-fiber`) that exercises concurrent Fiber SQL timing aggregation under `:fiber` versus `:thread` isolation when IsolatedExecutionState is available.

Accept measured baselines (n = 3 samples, `SCENARIO=fiber`, `BENCH_FIBER_N=3000`, `BENCH_FIBER_COUNT=8`, `SQL_EVENTS=8`, Ruby 4.0.7 arm64-darwin).

## Effects

On Rails 7.1+, Falcon-style hosts that set Rails Fiber isolation get per-Fiber `:grape_db_runtime`, `:grape_db_calls`, and `:grape_db_tracking` without gem changes. Rails 7.0 remains thread-local by design.

Median of three host samples (`benchmarks/output/fiber_sample_{1,2,3}.log`):

| Series | median ops/s | median wall (s) | alloc |
| --- | ---: | ---: | ---: |
| `baseline_fiber_sequential` | 38017.0 | 0.0789 | 1535262 |
| `baseline_fiber_concurrent` | 34288.5 | 0.0875 | 1554357 |
| `baseline_thread_concurrent_fibers` | 33751.1 | 0.0889 | 1548189 |

Fiber concurrent isolation is about **1.02×** the ops/s of the same interleaved Fiber workload under `:thread`. Sequential Fiber timings stay in the same band as concurrent series.

## Next

- Keep README wording that timings follow IsolatedExecutionState.
- Re-run `make bench-fiber` when `Timings` storage changes.

## Source

- `lib/grape_rails_logger/timings.rb`
- `README.md` (IsolatedExecutionState note)
- `spec/grape_timings_spec.rb`
- `benchmarks/load.rb` (`SCENARIO=fiber`)
- `benchmarks/output/fiber_sample_1.log`
- `benchmarks/output/fiber_sample_2.log`
- `benchmarks/output/fiber_sample_3.log`
