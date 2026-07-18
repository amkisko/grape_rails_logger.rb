# Request logging fixes for 1.2.1

## Participants

- amkisko

## Decisions

- Cut patch 1.2.1 for post-1.2.0 logging correctness and TRACE behavior fixes.
- Keep product CHANGELOG on operator-visible outcomes; leave CI, appraisal, and agent tooling out of CHANGELOG.md.
- Read TRACE from ENV at DebugTracer call time instead of freezing it at load.

## Effects

- StatusExtractor maps exception subclasses via ancestor name lookup without constantize per map entry.
- EndpointWrapper keeps the first downstream response when instrumentation fails after the handler, and warns in development.
- Timings.track_grape_request scopes sql.active_record aggregation to in-flight Grape requests.
- effective_config caches synthesized Rails config while values are unchanged.
- Railtie reuses subscriber_instance_for(subscriber_class).
- Integration specs boot a minimal Rails app; release still uses POLYRUN_COVERAGE on the unit suite.
- CHANGELOG.md and VERSION set to 1.2.1 (2026-07-18).

## Next

- Run make release or usr/bin/release.rb when ready to publish.
- Confirm RubyGems push and GitHub release tag 1.2.1.

## Source

- Commits since tag 1.2.0 on main, including status, timing, instrumentation, and DebugTracer TRACE fixes.
- Coverage gate failure that exposed TRACE_ENABLED load-time freeze.
