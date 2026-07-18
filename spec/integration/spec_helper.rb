ENV["RAILS_ENV"] ||= "test"

require "bundler/setup"
require "logger"
require "active_support"
require "active_support/core_ext/string/inquiry"
require "active_support/time"
require "rails"
require "grape"

require_relative "../support/logger_stub"

module GrapeRailsLoggerIntegrationApp
  class Application < Rails::Application
    config.root = File.expand_path("../..", __dir__)
    config.load_defaults "#{Rails::VERSION::MAJOR}.#{Rails::VERSION::MINOR}"
    config.eager_load = false
    config.consider_all_requests_local = true
    config.secret_key_base = ("0" * 64)
    config.filter_parameters += [:password]
  end
end

GrapeRailsLoggerIntegrationApp::Application.initialize!

require "grape_rails_logger"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around { |example| Time.use_zone("UTC") { example.run } }
end
