# Engineering and prose audit before 1.2.3 publish

## Participants

Andrei Makarov (@amkisko)

## Decisions

Re-audit main for the unpublished 1.2.3 cut. Include member double-dispatch guards, logger write success signaling, manual param key-only filtering, SQL Event allocation guard, response status preference, release gates, pull_request CI, and ASCII docs prose. Leave tag and RubyGems publish to make release after commit.

## Effects

Pipeline: Rack/Grape request -> EndpointWrapper / DebugTracer -> Timings + ActiveSupport::Notifications -> Subscriber -> logger. Boundary mode covered double-dispatch and param filtering. Resource and identification modes: no new person identifiers in gem logs. Queue, worker, learned-system, and physical plant modes skipped (absent).

Ranked fixes applied:

1. Downstream started/completed guards in `EndpointWrapper` and `DebugTracer` (high confidence, observed).
2. Boolean success from `safe_log` / `log_data` (high confidence, observed).
3. Key-only manual param filter aligned toward Rails defaults (high confidence, observed).
4. Prefer integer `#status` before `#to_a` (medium confidence, observed).
5. `Timings.record_sql_notification` skips Event allocation when inactive (high confidence, observed).
6. Changelog heading and confirmation specs; CHANGELOG dated 2026-11-03.
7. ASCII and marketing-tone pass on README, CHANGELOG, gemspec; fix stale `usr/docs/` Source paths.

Deferred (documented in the issue): production failure signal, fallback as request exception, rack.input re-parse, subscriber split, nested Timings reset, exception field filtering.

Checks observed in this session:

- bundle exec rubocop on touched Ruby files: 12 files, no offenses.
- bundle exec rbs validate: ok.
- bundle exec rspec: 298 examples, 0 failures, 1 pending (integration skip).
- bundle exec polyrun parallel-rspec --workers 5 --merge-failures: exit 0; coverage/merged-summary.txt 86.47% lines (505 / 584) across 8 files.
- gem build grape_rails_logger.gemspec and Gem::Package#verify for 1.2.3: ok.

## Next

Commit, then make release.

## Source

- docs/issues/20261103172128_engineering-prose-release-audit.md
- CHANGELOG.md section 1.2.3 (2026-11-03)
