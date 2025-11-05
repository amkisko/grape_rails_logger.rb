require "simplecov"
SimpleCov.start do
  add_filter "/spec/"
  add_filter { |source_file| source_file.lines.count < 5 }
end

require "simplecov-cobertura"
SimpleCov.formatter = SimpleCov::Formatter::CoberturaFormatter

require "bundler/setup"
require "logger" # Required for Ruby 3.1+ where Logger is a separate gem
require "climate_control"
require "active_support"
require "active_support/core_ext/string/inquiry"
require "active_support/core_ext/object/try"
require "active_support/notifications"
# Load parameter filter if available (Rails 6.1+)
begin
  require "active_support/parameter_filter"
rescue LoadError
  # ParameterFilter not available in this Rails version, that's okay
end
require "grape"

Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require_relative f }

require "grape_rails_logger"

# Note: ActiveSupport::Configurable deprecation warning may appear from Grape dependency
# This is expected and comes from third-party code, not this gem

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
