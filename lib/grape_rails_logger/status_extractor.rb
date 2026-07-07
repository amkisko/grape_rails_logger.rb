module GrapeRailsLogger
  # Shared utility for extracting HTTP status codes from exceptions
  module StatusExtractor
    module_function

    # Common exception to status code mappings
    EXCEPTION_STATUS_MAP = {
      "ActiveRecord::RecordNotFound" => 404,
      "ActiveRecord::RecordNotUnique" => 409,
      "ActiveRecord::RecordInvalid" => 422,
      "ActiveRecord::StatementInvalid" => 422,
      "ActionController::RoutingError" => 404,
      "ActionController::MethodNotAllowed" => 405,
      "ActionController::NotImplemented" => 501,
      "ActionController::UnknownFormat" => 406,
      "ActionController::BadRequest" => 400,
      "ActionController::ParameterMissing" => 400
    }.freeze

    # Extracts HTTP status code from an exception
    #
    # @param e [Exception] The exception to extract status from
    # @return [Integer] HTTP status code, defaults to 500
    def extract_status_from_exception(e)
      inline = inline_status_from_exception(e)
      return inline if inline.is_a?(Integer)

      map_exception_to_status(e.class) || 500
    end

    def inline_status_from_exception(e)
      return e.status if e.respond_to?(:status) && e.status.is_a?(Integer)

      if e.instance_variable_defined?(:@status)
        status = e.instance_variable_get(:@status)
        return status if status.is_a?(Integer)
      end

      if e.respond_to?(:options) && e.options.is_a?(Hash)
        return e.options[:status] if e.options[:status].is_a?(Integer)
      end

      nil
    end

    # Walk exception class and ancestors — O(ancestors) hash lookups, no constantize per map entry.
    # Non-Module classes (e.g. test doubles) use a single-element chain.
    def map_exception_to_status(e_class)
      chain = if Module === e_class
        e_class.ancestors
      else
        [e_class]
      end
      chain.each do |mod|
        next unless mod.respond_to?(:name)

        name = mod.name
        next if name.to_s.empty?

        status = EXCEPTION_STATUS_MAP[name]
        return status if status
      end
      nil
    end
    private_class_method :inline_status_from_exception, :map_exception_to_status
  end
end
