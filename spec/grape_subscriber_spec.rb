require "spec_helper"
require "rack/mock"
require_relative "support/logger_stub"

RSpec.describe GrapeRailsLogger::GrapeRequestLogSubscriber do
  let(:logger) { TestLogger.new }

  before do
    Rails._logger = logger
  end

  it "logs successful request with all fields" do
    app = Class.new(Grape::API) do
      format :json
      params do
        optional :username
        optional :email
      end
      post("/users") { {id: 1} }
    end

    Rack::MockRequest.new(app).post("/users", params: {username: "bob", email: "bob@example.com"})

    entry = logger.lines.find { |l| l.is_a?(Hash) }
    expect(entry).to be_a(Hash)
    expect(entry[:method]).to eq("POST")
    expect(entry[:path]).to eq("/users")
    expect(entry[:status]).to be_a(Integer)
    expect(entry[:params]).to be_a(Hash)
  end

  it "logs exception info for unhandled exceptions" do
    app = Class.new(Grape::API) do
      format :json
      get("/boom") { raise ArgumentError, "bad" }
    end

    expect { Rack::MockRequest.new(app).get("/boom") }.to raise_error(ArgumentError)

    expect(logger.lines.any? { |o| o.is_a?(Hash) && o[:exception] && o[:exception][:class] == "ArgumentError" }).to be true
  end

  it "handles edge cases gracefully" do
    # Test nil logger scenario - EndpointWrapper creates fallback logger to stdout
    # This is expected behavior: the gem should always have a logger available
    allow(Rails).to receive(:logger).and_return(nil)
    
    app = Class.new(Grape::API) do
      format :json
      get("/test") { raise StandardError, "test" }
    end
    # The request should still work - subscriber handles errors gracefully
    # Note: Error will be logged to stderr via fallback logger (expected behavior)
    expect { Rack::MockRequest.new(app).get("/test") }.to raise_error(StandardError)

    # Test subscriber error handling - subscriber should not raise errors
    subscriber = GrapeRailsLogger::GrapeRequestLogSubscriber.new
    allow(subscriber).to receive(:build_request).and_raise(StandardError, "Simulated error")
    event = ActiveSupport::Notifications::Event.new("grape.request", Time.now, Time.now + 0.01, "1", {
      env: {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/test"},
      logger: nil # Explicitly pass nil logger to test subscriber's nil handling
    })
    # Subscriber should handle errors gracefully without raising
    expect { subscriber.grape_request(event) }.not_to raise_error
  end
end
