module GrapeRailsLogger
  # Optional middleware for detailed request tracing when TRACE env var is set
  #
  # Requires the 'debug' gem to be installed. If TRACE is not set or Debug class
  # is unavailable, this middleware passes through without tracing.
  #
  # This middleware is completely exception-safe: any error in tracing will
  # cause the middleware to pass through without tracing, never breaking requests.
  #
  # @example Usage
  #   class API < Grape::API
  #     use GrapeRailsLogger::DebugTracer  # Only traces when TRACE=1
  #   end
  class DebugTracer < ::Grape::Middleware::Base
    def call!(env)
      # Read TRACE at call time so process env (and test ClimateControl) apply after load
      return @app.call(env) unless ENV["TRACE"]

      # Try to trace, but if anything fails, just pass through
      trace_request(env) do
        @app.call(env)
      end
    end

    private

    def trace_request(env)
      # Check if Debug is available before attempting to use it
      unless defined?(Debug)
        log_debug_unavailable
        return yield
      end

      request_method = safe_string(env["REQUEST_METHOD"])
      request_path = safe_string(env["PATH_INFO"] || env["REQUEST_PATH"])
      file_prefix = sanitize_file_prefix(request_method, request_path)
      context = [request_method, request_path].compact.join(" ")

      downstream_started = false
      downstream_completed = false
      downstream_response = nil

      begin
        Debug.new(
          with_sql: true,
          with_stack: false,
          store_file: true,
          file_prefix: file_prefix,
          context: context
        ).trace do
          downstream_started = true
          downstream_response = yield
          downstream_completed = true
          downstream_response
        end
        downstream_response
      rescue => e
        log_trace_error(e)
        raise if downstream_started && !downstream_completed
        return downstream_response if downstream_completed

        yield
      end
    end

    def sanitize_file_prefix(method, path)
      [method, path].compact.join("_").downcase.gsub(/[^a-z0-9_]+/, "_").slice(0, 100)
    end

    def safe_string(value)
      value&.to_s
    rescue
      nil
    end

    def log_debug_unavailable
      return unless defined?(Rails) && Rails.logger

      Rails.logger.error("DebugTracer: Debug class not available. Install debug gem or disable TRACE.")
    rescue
      # Ignore logger errors - never raise from logging
    end

    def log_trace_error(error)
      return unless defined?(Rails) && Rails.logger

      Rails.logger.error("DebugTracer: Error during trace - #{error.class}: #{error.message}")
    rescue
      # Silently fail - debug tracing should never break requests
    end
  end
end
