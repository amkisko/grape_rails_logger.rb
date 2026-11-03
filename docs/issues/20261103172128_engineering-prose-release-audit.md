# Engineering and prose audit before 1.2.3 publish

## Participants

Andrei Makarov (@amkisko)

## Decisions

Re-audit main for the unpublished 1.2.3 cut after the 2026-10-28 release-tooling pass. Include member double-dispatch guards already in the worktree, logger write success signaling, manual param key-only filtering, SQL Event allocation guard, response status preference, release confirmation and changelog gates, pull_request CI, and ASCII docs prose. Leave tag and RubyGems publish to `make release` after commit.

## Effects

Pipeline: Rack/Grape request -> EndpointWrapper / DebugTracer -> Timings + ActiveSupport::Notifications -> Subscriber -> logger. Boundary mode covered double-dispatch and param filtering. Resource and identification modes: no new person identifiers in gem logs. Queue, worker, learned-system, and physical plant modes skipped (absent).

Ranked fixes applied:

1. Keep tracing and request instrumentation from dispatching a failed request more than once (prior worktree; high confidence, observed).
2. Return false from `safe_log` / `log_data` when write fails or no logger exists (high confidence, observed).
3. Manual param filter by key only; expand key patterns toward Rails `filter_parameters` defaults (high confidence, observed).
4. Prefer `#status` over `#to_a` for non-Array Rack response status (medium confidence, observed).
5. Skip SQL `Event` allocation outside an active Grape request via `Timings.record_sql_notification` (high confidence, observed).
6. Changelog heading and confirmation specs; CHANGELOG dated 2026-11-03; prose pass on README, gemspec, and stale `usr/docs/` Source paths.

Deferred:

- Rate-limited warn or counter when instrumentation or subscriber write fails in production.
- Fallback subscriber path publishing logging bugs as request `:error` / `exception`.
- Cap or drop post-request `rack.input` JSON re-parse in `extract_params`.
- Split `subscriber.rb` shared request-field extraction / file ownership.
- Nested `Timings.track_grape_request` resetting outer DB counters.
- Exception message / backtrace not passed through param filter.

## Next

Commit, then `make release`.

## Source

- docs/reviews/20261103172128_engineering-prose-release-audit.md
- CHANGELOG.md section 1.2.3 (2026-11-03)
- Prior pass: docs/reviews/20261028_engineering-audit-release-preparation.md
