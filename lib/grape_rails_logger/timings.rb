module GrapeRailsLogger
  # Thread-safe storage for DB timing metrics per request
  module Timings
    # Use IsolatedExecutionState for Rails 7.1+ thread/Fiber safety
    # Falls back to Thread.current for Rails 6-7.0
    if defined?(ActiveSupport::IsolatedExecutionState)
      def self.execution_state
        ActiveSupport::IsolatedExecutionState
      end
    else
      def self.execution_state
        Thread.current
      end
    end

    def self.reset_db_runtime
      state = execution_state
      state[:grape_db_runtime] = 0.0
      state[:grape_db_calls] = 0
    end

    def self.track_grape_request
      state = execution_state
      previous_tracking = state[:grape_db_tracking]
      state[:grape_db_tracking] = true
      reset_db_runtime
      yield
    ensure
      state[:grape_db_tracking] = previous_tracking
    end

    def self.grape_request_active?
      !!execution_state[:grape_db_tracking]
    end

    def self.db_runtime
      execution_state[:grape_db_runtime] ||= 0
    end

    def self.db_calls
      execution_state[:grape_db_calls] ||= 0
    end

    def self.append_db_runtime(event_or_duration)
      state = execution_state
      return unless state[:grape_db_tracking]

      duration =
        if event_or_duration.is_a?(Numeric)
          event_or_duration
        else
          event_or_duration.duration
        end
      duration = duration.to_f if duration.is_a?(Numeric)
      state[:grape_db_runtime] = (state[:grape_db_runtime] || 0) + duration
      state[:grape_db_calls] = (state[:grape_db_calls] || 0) + 1
    end

    # Railtie SQL subscribe entry: skip Event allocation when no Grape request is tracked.
    def self.record_sql_notification(*args)
      state = execution_state
      return unless state[:grape_db_tracking]

      duration = sql_notification_duration(args)
      append_db_runtime(duration.nil? ? ActiveSupport::Notifications::Event.new(*args) : duration)
    end

    def self.sql_notification_duration(args)
      case args.length
      when 5
        d = args[2] - args[1]
        (d.is_a?(Numeric)) ? d.to_f : d
      when 1
        arg = args.first
        d = arg.duration if arg.respond_to?(:duration)
        (d.is_a?(Numeric)) ? d.to_f : d
      end
    end
    private_class_method :sql_notification_duration
  end
end
