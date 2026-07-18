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
      state[:grape_db_runtime] = 0
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

    def self.append_db_runtime(event)
      state = execution_state
      return unless state[:grape_db_tracking]

      state[:grape_db_runtime] = (state[:grape_db_runtime] || 0) + event.duration
      state[:grape_db_calls] = (state[:grape_db_calls] || 0) + 1
    end
  end
end
