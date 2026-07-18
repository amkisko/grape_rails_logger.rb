polyrun_cov_measure =
  ENV["POLYRUN_COVERAGE_DISABLE"] != "1" &&
  %w[1 true yes].include?(ENV["POLYRUN_COVERAGE"]&.to_s&.downcase)

if polyrun_cov_measure
  require "coverage"
  branch = %w[1 true yes].include?(ENV["POLYRUN_COVERAGE_BRANCHES"]&.to_s&.downcase)
  ::Coverage.start(lines: true, branches: branch)
end

if polyrun_cov_measure
  require "polyrun/coverage/rails"
  Polyrun::Coverage::Rails.start!(root: File.expand_path("..", __dir__))
end

require "bundler/setup"
require "logger" # Required for Ruby 3.1+ where Logger is a separate gem
require "climate_control"
require "active_support"
require "active_support/core_ext/string/inquiry"
require "active_support/core_ext/object/try"
require "active_support/time"
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
  config.around do |example|
    Time.use_zone("UTC") { example.run }
  end

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
require "polyrun/rspec"
Polyrun::RSpec.install_sharded_formatter_compat!
Polyrun::RSpec.install_failure_fragments!
Polyrun::RSpec.install_worker_ping!
Polyrun::RSpec.install_example_debug!
Polyrun::RSpec.install_example_rails_logging!
Polyrun::RSpec.install_example_timeout!
if %w[1 true yes].include?(ENV["POLYRUN_SPEC_QUALITY"]&.to_s&.downcase)
  Polyrun::RSpec.install_spec_quality!
end
