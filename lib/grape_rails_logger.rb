require "active_support"
require "active_support/notifications"
require "grape"

# Load all required files first to ensure constants are available
# This must happen before the module definition (like other gems do)
require "grape_rails_logger/version"
require "grape_rails_logger/timings"
require "grape_rails_logger/status_extractor"
require "grape_rails_logger/subscriber"
require "grape_rails_logger/endpoint_patch"
require "grape_rails_logger/endpoint_wrapper"
require "grape_rails_logger/debug_tracer"

module GrapeRailsLogger
  # Distinguish "Rails config did not define this key" from a real nil/false value
  EFFECTIVE_CONFIG_ATTR_MISSING = Object.new.freeze

  # Configuration for GrapeRailsLogger
  #
  # When running in Rails, use Rails.application.config.grape_rails_logger instead:
  #
  # @example Configure in Rails initializer
  #   # config/initializers/grape_rails_logger.rb
  #   Rails.application.config.grape_rails_logger.enabled = true
  #   Rails.application.config.grape_rails_logger.subscriber_class = CustomSubscriber
  #
  # @example Standalone usage (non-Rails)
  #   GrapeRailsLogger.config.enabled = false
  class Config
    attr_accessor :enabled, :subscriber_class, :logger, :tag

    def initialize
      @enabled = true
      @subscriber_class = GrapeRequestLogSubscriber
      @logger = nil # Default to nil, will use Rails.logger if available
      @tag = "Grape" # Default tag for TaggedLogging
    end
  end

  # Global configuration instance (for non-Rails usage)
  #
  # @return [Config] The configuration object
  def self.config
    @config ||= Config.new
  end

  # Configure the logger (for non-Rails usage)
  #
  # @yield [config] Yields the configuration object
  # @example
  #   GrapeRailsLogger.configure do |config|
  #     config.enabled = false
  #   end
  def self.configure
    yield config
  end

  # Get the effective configuration (Rails-aware)
  #
  # Caches the synthesized {Config} while Rails config values are unchanged
  # (avoids allocating a new {Config} on every call).
  #
  # @return [Config] The active configuration object
  def self.effective_config
    if defined?(Rails) && Rails.application && Rails.application.config.respond_to?(:grape_rails_logger)
      rails_config = Rails.application.config.grape_rails_logger
      signature = rails_effective_config_signature(rails_config)
      if @rails_effective_config_signature == signature && @rails_effective_config
        @rails_effective_config
      else
        @rails_effective_config_signature = signature
        @rails_effective_config = build_effective_config_from_rails(rails_config)
      end
    else
      # Fall back to module-level config for non-Rails usage
      config
    end
  end

  # @api private
  def self.build_effective_config_from_rails(rails_config)
    config_obj = Config.new
    config_obj.enabled = rails_config.enabled if rails_config.respond_to?(:enabled)
    config_obj.subscriber_class = rails_config.subscriber_class if rails_config.respond_to?(:subscriber_class)
    config_obj.logger = rails_config.logger if rails_config.respond_to?(:logger)
    config_obj.tag = rails_config.tag if rails_config.respond_to?(:tag)
    config_obj
  end

  def self.rails_effective_config_signature(rails_config)
    [
      rails_config.respond_to?(:enabled) ? rails_config.enabled : EFFECTIVE_CONFIG_ATTR_MISSING,
      rails_config.respond_to?(:subscriber_class) ? rails_config.subscriber_class : EFFECTIVE_CONFIG_ATTR_MISSING,
      rails_config.respond_to?(:logger) ? rails_config.logger : EFFECTIVE_CONFIG_ATTR_MISSING,
      rails_config.respond_to?(:tag) ? rails_config.tag : EFFECTIVE_CONFIG_ATTR_MISSING
    ]
  end
  private_class_method :build_effective_config_from_rails, :rails_effective_config_signature

  # Reuse one subscriber instance per class — {GrapeRequestLogSubscriber} has no per-request ivars.
  #
  # @api private
  def self.subscriber_instance_for(subscriber_class)
    @subscriber_instances ||= {}
    @subscriber_instances[subscriber_class] ||= subscriber_class.new
  end
end

# Load Railtie for Rails integration
# Rails will automatically discover and initialize this Railtie
require "grape_rails_logger/railtie"
