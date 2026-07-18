require "logger"

module GrapeRailsLogger
  # Wraps the final Rack app returned by Grape::Endpoint#build_stack to capture
  # the response AFTER Error middleware has fully processed it (including rescue_from handlers).
  #
  # This is the correct place to log because:
  # 1. Error middleware wraps everything and processes exceptions
  # 2. rescue_from handlers run and set the correct status
  # 3. The final response is returned with the correct status
  # 4. We capture it here, AFTER all processing is complete
  class EndpointWrapper
    def initialize(app, endpoint)
      @app = app
      @endpoint = endpoint
    end

    def call(env)
      return @app.call(env) unless GrapeRailsLogger.effective_config.enabled

      logger = resolve_logger
      downstream_response = nil

      Timings.track_grape_request do
        # Wrap the entire request in ActiveSupport::Notifications
        # This ensures we capture the final response AFTER Error middleware processes exceptions
        ActiveSupport::Notifications.instrument("grape.request", env: env, logger: logger) do |payload|
          # Call the wrapped app - Error middleware will process exceptions and return final response
          # NOTE: We do NOT read the body here - Grape will process it and parse params
          # We'll extract params later from already-parsed sources (endpoint.request.params)
          downstream_response = @app.call(env)

          # NOW collect all data AFTER Error middleware has processed exceptions
          # At this point, response contains the final Rack response with correct status
          # AND Grape has already parsed the params, so we can safely access endpoint.request.params
          collect_response_metadata(downstream_response, env, payload)

          # Return the response - subscriber will log it
          downstream_response
        end
      end
    rescue => e
      handle_instrumentation_error(e)
      return downstream_response if downstream_response

      @app.call(env)
    end

    private

    def resolve_logger
      config = GrapeRailsLogger.effective_config
      config.logger || (defined?(Rails) && Rails.logger) || Logger.new($stdout)
    end

    def collect_response_metadata(response, env, payload)
      # Extract status from response - this is the FINAL status after Error middleware
      status = extract_status_from_response(response)
      payload[:status] = status if status.is_a?(Integer)
      payload[:response] = response

      # Extract endpoint info for exception tracking
      endpoint = env[Grape::Env::API_ENDPOINT] if env.is_a?(Hash)
      if endpoint
        # Check for exception info that Grape might have stored
        if endpoint.respond_to?(:options) && endpoint.options.is_a?(Hash)
          exception = endpoint.options[:exception] || endpoint.options["exception"] ||
            endpoint.options[:error] || endpoint.options["error"]
          payload[:exception_object] = exception if exception.is_a?(Exception)
        end
        if endpoint.respond_to?(:exception) && endpoint.exception.is_a?(Exception) && !payload[:exception_object]
          payload[:exception_object] = endpoint.exception
        end
      end

      # Capture DB metrics (already collected by Timings module)
      payload[:db_runtime] = Timings.db_runtime
      payload[:db_calls] = Timings.db_calls

      # Note: The subscriber will extract all other data (method, path, format, etc.)
      # from the env using build_request and other helper methods
    end

    def extract_status_from_response(response)
      return nil unless response

      if response.is_a?(Array) && response[0].is_a?(Integer)
        response[0]
      elsif response.respond_to?(:to_a)
        array = response.to_a
        array[0] if array.is_a?(Array) && array[0].is_a?(Integer)
      elsif response.respond_to?(:status) && response.status.is_a?(Integer)
        response.status
      end
    end

    def handle_instrumentation_error(error)
      return unless defined?(Rails) && Rails.env.development?

      resolve_logger.warn("GrapeRailsLogger: instrumentation failed - #{error.class}: #{error.message}")
    rescue
      # Never let error reporting break requests
    end
  end
end
