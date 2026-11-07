#!/usr/bin/env ruby
# frozen_string_literal: true

# Pressure load bench for GrapeRailsLogger hot paths (log payload build + SQL timings).
#
# Usage:
#   bundle exec ruby benchmarks/load.rb
#   BENCH_REPS=400 PARAM_KEYS=32 TARGET_FACTOR=0.85 bundle exec ruby benchmarks/load.rb
#
# Env:
#   BENCH_REPS — repetitions per scenario row
#   PARAM_KEYS — top-level param keys for build_log_data (default 32)
#   SQL_EVENTS — sql.active_record notifications per rep for Timings bench (default 34)
#   TARGET_FACTOR — ceiling vs baseline metrics (default 0.85, from Polyrun::Benchmark::Pressure)
#   PRESSURE_POLYRUN_LIB — optional path to polyrun lib/ (default: gem via LOAD_PATH)
#
# Scenarios: flat params, nested params (+ ParameterFilter deep_dup),
# synthetic sql.active_record timings aggregation.
# Fiber scenario (SCENARIO=fiber): concurrent Fiber DB timings under
# ActiveSupport::IsolatedExecutionState isolation_level :fiber vs :thread when available.

require "bundler/setup"

require "active_support"
require "active_support/core_ext/object/blank"
require "active_support/time"
require "active_support/notifications"

begin
  require "active_support/parameter_filter"
rescue LoadError
  # optional in older stacks
end

require "grape"

gem_lib = File.expand_path("../lib", __dir__)
$LOAD_PATH.unshift(gem_lib) unless $LOAD_PATH.include?(gem_lib)

require "grape_rails_logger"
require File.expand_path("../spec/support/rails_stub", __dir__)

sibling_polyrun_lib = File.expand_path("../../polyrun.rb/lib", __dir__)
polyrun_lib = ENV["PRESSURE_POLYRUN_LIB"].to_s
polyrun_lib = sibling_polyrun_lib if polyrun_lib.empty? && File.directory?(sibling_polyrun_lib)
polyrun_lib = nil if polyrun_lib.empty?

if polyrun_lib && File.directory?(polyrun_lib)
  $LOAD_PATH.unshift(polyrun_lib) unless $LOAD_PATH.include?(polyrun_lib)
end

begin
  require "polyrun/benchmark/pressure"
rescue LoadError => e
  warn "Could not load polyrun/benchmark/pressure (#{e.message})."
  warn "Install a Polyrun build that ships lib/polyrun/benchmark/pressure.rb or set PRESSURE_POLYRUN_LIB to that lib/ directory."
  raise
end

Time.zone = "UTC"

module GrapeRailsLogger
  module Bench
    module Load
      module_function

      def run!
        scenario = ENV.fetch("SCENARIO", "matrix")
        reps = env_int("BENCH_REPS", 280)
        param_keys = env_int("PARAM_KEYS", 32)
        sql_events = env_int("SQL_EVENTS", 34)
        factor = ENV.fetch("TARGET_FACTOR", Polyrun::Benchmark::Pressure::DEFAULT_TARGET_FACTOR.to_s).to_f

        results =
          case scenario
          when "matrix"
            puts "GrapeRailsLogger pressure matrix reps=#{reps} param_keys=#{param_keys} sql_events=#{sql_events} target_factor=#{factor}"
            run_matrix!(reps, param_keys, sql_events, factor)
          when "fiber"
            run_fiber_matrix!
          else
            raise ArgumentError, "Unknown SCENARIO=#{scenario.inspect} (matrix|fiber)"
          end

        root = File.expand_path("..", __dir__)
        path = Polyrun::Benchmark::Pressure.write_results!(results, repository_root: root)
        results.each { |row| puts row["report"] }
        puts "wrote #{path}"
        code = (results.any? { |row| row["pass"] == false }) ? 1 : 0
        exit code
      end

      def run_fiber_matrix!
        fiber_n = env_int("BENCH_FIBER_N", 3000)
        fiber_count = env_int("BENCH_FIBER_COUNT", 8)
        sql_events = env_int("SQL_EVENTS", 8)
        puts "GrapeRailsLogger fiber bench fiber_n=#{fiber_n} fiber_count=#{fiber_count} sql_events=#{sql_events}"

        unless defined?(ActiveSupport::IsolatedExecutionState)
          warn "ActiveSupport::IsolatedExecutionState unavailable; fiber scenario needs Rails 7.1+"
          return []
        end

        [
          measure_fiber_sql!("baseline_fiber_sequential", fiber_n, sql_events: sql_events, concurrent: false, isolation: :fiber),
          measure_fiber_sql!("baseline_fiber_concurrent", fiber_n, sql_events: sql_events, concurrent: true, fiber_count: fiber_count, isolation: :fiber),
          measure_fiber_sql!("baseline_thread_concurrent_fibers", fiber_n, sql_events: sql_events, concurrent: true, fiber_count: fiber_count, isolation: :thread)
        ]
      end

      def with_ies_isolation(level)
        previous = ActiveSupport::IsolatedExecutionState.isolation_level
        ActiveSupport::IsolatedExecutionState.isolation_level = level
        yield
      ensure
        ActiveSupport::IsolatedExecutionState.isolation_level = previous
        GrapeRailsLogger::Timings.reset_db_runtime
      end

      def measure_fiber_sql!(label, ops, sql_events:, concurrent:, isolation:, fiber_count: 8)
        with_ies_isolation(isolation) do
          name = "sql.active_record"
          # Prefer wall Time over Time.zone: switching IsolatedExecutionState.isolation_level
          # can leave zone unset for the measuring Fiber.
          finish_base = Time.now.utc
          Polyrun::Benchmark::Pressure.measure(
            label: label,
            ops: ops,
            extras: {
              "isolation_level" => isolation.to_s,
              "fiber_count" => concurrent ? fiber_count : 1,
              "sql_events" => sql_events
            }
          ) do
            if concurrent
              i = 0
              while i < ops
                batch = [fiber_count, ops - i].min
                fibers = batch.times.map do |f|
                  idx = i + f
                  Fiber.new do
                    GrapeRailsLogger::Timings.track_grape_request do
                      sql_events.times do |j|
                        start_t = finish_base + ((idx * sql_events + j) * 0.0001)
                        finish_t = start_t + 0.002
                        Fiber.yield if j.zero?
                        GrapeRailsLogger::Timings.record_sql_notification(
                          name, start_t, finish_t, "bench#{idx}-#{j}", {}
                        )
                      end
                    end
                  end
                end
                fibers.each(&:resume)
                fibers.each(&:resume)
                i += batch
              end
            else
              ops.times do |idx|
                GrapeRailsLogger::Timings.track_grape_request do
                  sql_events.times do |j|
                    start_t = finish_base + ((idx * sql_events + j) * 0.0001)
                    finish_t = start_t + 0.002
                    GrapeRailsLogger::Timings.record_sql_notification(
                      name, start_t, finish_t, "bench#{idx}-#{j}", {}
                    )
                  end
                end
              end
            end
          end
        end
      end

      def run_matrix!(reps, param_keys, sql_events, factor)
        flat_b, flat_p = run_log_pair!(reps, param_keys, factor, nested: false, name: "log_flat")
        nest_b, nest_p = run_log_pair!(reps, param_keys, factor, nested: true, name: "log_nested")
        sql_b, sql_p = run_sql_pair!(reps, sql_events, factor)
        [flat_b, flat_p, nest_b, nest_p, sql_b, sql_p]
      end

      # Single-row measure for calibrate meter (low rep count; order by wall only).
      def measure_log_scenario!(reps:, param_keys:, nested:, label:)
        setup_filter_config!
        run_log_build!(reps, param_keys, 1.0, label: label, targets: nil, nested: nested)
      end

      def measure_sql_scenario!(reps:, sql_events:, label:)
        run_sql_timings!(reps, sql_events, label: label, targets: nil)
      end

      # ordered stages: [name, known_rank, callable] — known_rank must match increasing wall cost.
      # Use clearly separated work sizes so Process monotonic wall ordering matches rank (noise-safe).
      def calibrate_stages(
        reps_flat: 10,
        keys_flat: 4,
        reps_nested: 50,
        keys_nested: 40,
        reps_sql: 35,
        sql_ev: 220
      )
        [
          [
            "log_small_params",
            1,
            -> { measure_log_scenario!(reps: reps_flat, param_keys: keys_flat, nested: false, label: "calibrate_log_small") }
          ],
          [
            "log_nested_params",
            2,
            -> { measure_log_scenario!(reps: reps_nested, param_keys: keys_nested, nested: true, label: "calibrate_log_nested") }
          ],
          [
            "sql_timings",
            3,
            -> { measure_sql_scenario!(reps: reps_sql, sql_events: sql_ev, label: "calibrate_sql") }
          ]
        ]
      end

      def run_log_pair!(reps, param_keys, factor, nested:, name:)
        setup_filter_config!
        hotter_keys = [(param_keys * 1.5).ceil, param_keys + 1].max
        tag = nested ? "nested" : "flat"

        baseline = run_log_build!(
          reps,
          param_keys,
          factor,
          label: "baseline_#{name}_#{tag}",
          nested: nested
        )
        targets = Polyrun::Benchmark::Pressure.targets_from(baseline["metrics"], factor: factor)
        ops_b = baseline["ops"]
        ops_h = reps * hotter_keys
        scaled = scale_targets_for_ops(targets, ops_b, ops_h)
        # Heap / RSS deltas are noisy under micro-benches; enforce wall + CPU only.
        log_targets = scaled.slice("wall_s", "cpu_s")

        pressure = run_log_build!(
          reps,
          hotter_keys,
          factor,
          label: "pressure_#{name}_#{hotter_keys}_keys_#{tag}",
          targets: log_targets,
          nested: nested
        )

        [baseline, pressure]
      end

      def run_sql_pair!(reps, sql_events, factor)
        baseline = run_sql_timings!(
          reps,
          sql_events,
          label: "baseline_sql_timings"
        )
        hotter_sql = [(sql_events * 1.5).ceil, sql_events + 1].max
        targets = Polyrun::Benchmark::Pressure.targets_from(baseline["metrics"], factor: factor)
        ops_b = baseline["ops"]
        ops_h = reps * hotter_sql
        scaled = scale_targets_for_ops(targets, ops_b, ops_h)
        sql_targets = scaled.slice("wall_s", "cpu_s")

        pressure = run_sql_timings!(
          reps,
          hotter_sql,
          label: "pressure_sql_timings_#{hotter_sql}_events",
          targets: sql_targets
        )

        [baseline, pressure]
      end

      def run_log_build!(reps, param_keys, _factor, label:, targets: nil, nested: false)
        subscriber = GrapeRailsLogger::GrapeRequestLogSubscriber.new
        event, request, env = build_log_fixture(param_keys: param_keys, nested: nested)
        ops = reps * param_keys

        # Stabilize allocator/GC noise vs the measured window
        warm = (reps / 8).clamp(3, reps)
        warm.times { subscriber.send(:build_log_data, event, request, env) }

        Polyrun::Benchmark::Pressure.measure(label: label, ops: ops, extras: {"targets" => targets}) do
          reps.times { subscriber.send(:build_log_data, event, request, env) }
        end
      end

      def run_sql_timings!(reps, sql_events, label:, targets: nil)
        ops = reps * sql_events
        name = "sql.active_record"
        finish_base = Time.zone.now

        Polyrun::Benchmark::Pressure.measure(label: label, ops: ops, extras: {"targets" => targets}) do
          reps.times do
            GrapeRailsLogger::Timings.track_grape_request do
              sql_events.times do |i|
                start_t = finish_base + (i * 0.0001)
                finish_t = start_t + 0.002
                GrapeRailsLogger::Timings.record_sql_notification(
                  name,
                  start_t,
                  finish_t,
                  "bench#{i}",
                  {}
                )
              end
            end
          end
        end
      end

      def setup_filter_config!
        Rails.application.config.filter_parameters = %i[password secret token]
      end

      def build_log_fixture(param_keys:, nested:)
        param_hash = {}
        param_keys.times do |i|
          param_hash["field_#{i}"] = "value_#{i}"
        end
        param_hash["password"] = "sekret"
        if nested
          # Multi-level nesting so ParameterFilter + deep_dup stay on the hot path.
          param_hash["meta"] = {
            "inner_secret" => "x",
            "n" => 1,
            "deep" => {"a" => {"b" => {"c" => {"d" => "leaf"}}}}
          }
        end

        params_wrapper = ParamWrapper.new(param_hash)

        endpoint = Object.new
        endpoint.define_singleton_method(:request) do
          req = Object.new
          req.define_singleton_method(:params) { params_wrapper }
          req.define_singleton_method(:content_type) { "application/json" }
          req.define_singleton_method(:env) { {} }
          req
        end

        endpoint_options = {method: [:GET], path: ["/bench/:id"]}
        source_location = [Rails.root.join("app/api/bench.rb").to_s, 42]

        endpoint.define_singleton_method(:options) { endpoint_options }
        endpoint.define_singleton_method(:source) do
          src = Object.new
          src.define_singleton_method(:source_location) { source_location }
          src
        end
        endpoint.define_singleton_method(:status) { 200 }
        endpoint.define_singleton_method(:respond_to?) { |m, *_| [:options, :source, :status, :request].include?(m) }

        env = {
          "REQUEST_METHOD" => "GET",
          "PATH_INFO" => "/bench/1",
          "api.endpoint" => endpoint,
          Grape::Env::API_ENDPOINT => endpoint,
          "api.format" => ".json",
          "action_dispatch.request_id" => "bench-req"
        }

        payload = {
          env: env,
          db_runtime: 1.23,
          db_calls: 3,
          status: 200,
          response: [200, {"Content-Type" => "application/json"}, []]
        }

        request = Grape::Request.new(env)

        event = ActiveSupport::Notifications::Event.new(
          "grape.request",
          Time.zone.now,
          Time.zone.now + 0.01,
          "bench",
          payload
        )

        [event, request, env]
      end

      # Minimal params object compatible with Subscriber#extract_params
      class ParamWrapper
        def initialize(hash)
          @hash = hash
        end

        def to_unsafe_h
          @hash
        end

        def to_h
          @hash
        end

        def blank?
          @hash.blank?
        end
      end

      def scale_targets_for_ops(targets, baseline_ops, new_ops)
        return targets if baseline_ops.nil? || baseline_ops <= 0 || new_ops.nil?

        ratio = new_ops.to_f / baseline_ops
        targets.transform_values { |v| v.nil? ? nil : v * ratio }
      end

      def env_int(name, default)
        Integer(ENV.fetch(name, default.to_s))
      end
    end
  end
end

GrapeRailsLogger::Bench::Load.run! if $PROGRAM_NAME == __FILE__
