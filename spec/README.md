# Testing

## Commands

Full suite (matches CI: parallel shards via Polyrun):

```bash
make test
```

Lint (RuboCop and RBS):

```bash
make lint
```

Focused runs use plain RSpec:

```bash
bundle exec rspec spec/grape_subscriber_spec.rb
bundle exec rspec spec/grape_subscriber_spec.rb:42
```

See `polyrun.yml`. `make test` runs `hooks.before_suite` before specs.

## Layout

- `spec/` — subscriber, extraction, railtie, and compatibility specs
- `spec/support/` — shared helpers

## Guidelines

- Test public logging behavior and request metadata contracts, not private helpers.
- Mock only boundaries (time, HTTP, rack env), not methods on the class under test.
- Add or update specs before bugfixes; run `make lint && make test` before a PR.
- Coverage threshold: `config/polyrun_coverage.yml` when `POLYRUN_COVERAGE=1` (release script and CI coverage job).
