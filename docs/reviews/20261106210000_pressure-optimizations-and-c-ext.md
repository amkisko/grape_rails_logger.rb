# Pressure optimizations and C-extension probe

## Participants

Andrei Makarov (@amkisko)

## Scope

`grape-rails-logger.rb` after the pressure-cooker episode: remove `PressureEvolve` / `GRAPE_RL_PRESSURE_EVOLVE` from `lib/`, keep permanent subscriber/timings optimizations, confirm no custom C is warranted.

Host for cited numbers: Ruby 4.0.x, arm64-darwin. Host-relative, not SLOs.

## Decision: C extension

**Ship custom C extension: no.**

| Probe | Ruby median | Alternate | Why not ship |
| --- | ---: | --- | --- |
| `filter_params` (deep_dup + ParameterFilter) | **193 µs**/call | manual filter ~**1.10×** slower | ParameterFilter already owns matching/copy; custom C does not safely replace filter rules. |

## When to try C extensions again

Retry custom C only when measurement shows the hot path is (1) a large enough share of total time and (2) a tight loop over primitives that ParameterFilter does not already cover.

### Try again when

- A new hot path is linear over bytes/ints with a rare Ruby↔C boundary, not another param-filter wrapper.
- Custom C is a full semantic substitute and beats the current `filter_params` / timings path by clearly above ~20% median wall (n ≥ 3).
- Profile shows roughly ≥30–40% of time in one tight non-ParameterFilter function before writing `ext/`.

### Do not retry when

- The path already sits on ActiveSupport::ParameterFilter (and deep_dup of nested params).
- The bottleneck is Grape/Rails request I/O or SQL volume, not filter CPU.
- Platform/ABI/maintenance cost exceeds the measured gain.

### Gate before shipping

1. Load measure: named primary series dominates at L1.
2. Profile: one tight function outside ParameterFilter owns a large fraction of log-build time.
3. Throwaway C probe with the same semantics → only then add `ext/` if the full probe improves enough and tests stay green.

Short form: retry C for “new primitive loops”; skip C for “ParameterFilter and request plumbing.”

## Permanent Ruby optimizations (flags removed)

| Optimization | Effect (cited) |
| --- | --- |
| Cache `ParameterFilter`; `dup` instead of `deep_dup` for flat params | log-build pressure row stayed under tightened wall/cpu in cooker |
| `Timings.record_sql_notification` without allocating `Event` on 5-arg notify | higher SQL timing ops/s vs Event path |
| `env[Grape::Env::API_ENDPOINT]` only | no string-key fallback |
| Frozen `EMPTY_HASH` early returns | less `{}` alloc |
| `Integer(db_calls)`; Float DB runtime seed; single `execution_state` read | less coercion / double lookup |
| `nested_param_structure?` empty early out; String key `#downcase` without `to_s` | cheaper filter checks |

`PressureEvolve` removed. Specs: **298** examples green.

## Documentation cleanup

Removed cooker episode docs, evolve harnesses, and joint multi-gem review content from this repository. Retained light `benchmarks/load.rb`.

## Source

- `lib/grape_rails_logger/` permanent paths
- `filter_params` probe numbers above
