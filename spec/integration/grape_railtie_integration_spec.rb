require "rack/mock"

if defined?(Rails) && Rails.singleton_class.method_defined?(:_logger)
  RSpec.describe "GrapeRailsLogger Railtie integration", type: :integration do
    it "runs in an isolated process without the Rails test stub" do
      skip "boot the minimal Rails app in isolation: bundle exec rspec spec/integration"
    end
  end
else
  require_relative "spec_helper"

  RSpec.describe "GrapeRailsLogger Railtie integration", type: :integration do
    let(:logger) { TestLogger.new }

    before do
      Rails.logger = logger
    end

    it "loads the Railtie and patches Grape::Endpoint during after_initialize" do
      expect(defined?(GrapeRailsLogger::Railtie)).to be_truthy
      expect(Grape::Endpoint.ancestors).to include(GrapeRailsLogger::EndpointPatch)
    end

    it "exposes grape_rails_logger configuration on Rails.application" do
      config = Rails.application.config.grape_rails_logger

      expect(config.enabled).to be true
      expect(config.subscriber_class).to eq(GrapeRailsLogger::GrapeRequestLogSubscriber)
    end

    it "logs request metadata when a Grape route is hit through Railtie wiring" do
      api = Class.new(Grape::API) do
        format :json
        get("/railtie-health") { {ok: true} }
      end

      Rack::MockRequest.new(api).get("/railtie-health")

      entry = logger.hash_entries.last
      expect(entry).to include(method: "GET", path: "/railtie-health")
      expect(entry[:status]).to eq(200)
    end

    it "reuses the Railtie subscriber singleton" do
      subscriber_class = Rails.application.config.grape_rails_logger.subscriber_class
      first = GrapeRailsLogger.subscriber_instance_for(subscriber_class)
      second = GrapeRailsLogger.subscriber_instance_for(subscriber_class)

      expect(first).to be(second)
    end
  end
end
