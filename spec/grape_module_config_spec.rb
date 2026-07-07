require "spec_helper"
require_relative "support/logger_stub"

RSpec.describe GrapeRailsLogger do
  describe ".config" do
    it "returns a Config instance" do
      expect(described_class.config).to be_a(GrapeRailsLogger::Config)
    end

    it "returns the same instance on subsequent calls" do
      first = described_class.config
      second = described_class.config
      expect(first).to be(second)
    end
  end

  describe ".configure" do
    it "yields the config object" do
      config_obj = nil
      described_class.configure do |config|
        config_obj = config
      end
      expect(config_obj).to be_a(GrapeRailsLogger::Config)
      expect(config_obj).to be(described_class.config)
    end

    it "allows configuring enabled" do
      described_class.configure do |config|
        config.enabled = false
      end
      expect(described_class.config.enabled).to be false
    end

    it "allows configuring subscriber_class" do
      custom_subscriber = Class.new
      described_class.configure do |config|
        config.subscriber_class = custom_subscriber
      end
      expect(described_class.config.subscriber_class).to be(custom_subscriber)
    end

    it "allows configuring logger" do
      custom_logger = TestLogger.new
      described_class.configure do |config|
        config.logger = custom_logger
      end
      expect(described_class.config.logger).to be(custom_logger)
    end

    it "allows configuring tag" do
      described_class.configure do |config|
        config.tag = "CustomTag"
      end
      expect(described_class.config.tag).to eq("CustomTag")
    end
  end

  describe ".effective_config" do
    context "when Rails is available" do
      before do
        allow(Rails).to receive(:application).and_return(Rails.application)
        allow(Rails.application.config).to receive(:respond_to?).with(:grape_rails_logger).and_return(true)
      end

      it "uses Rails config when available" do
        rails_config = double(
          enabled: false,
          subscriber_class: Class.new,
          logger: TestLogger.new,
          tag: "RailsTag",
          respond_to?: true
        )
        allow(Rails.application.config).to receive(:grape_rails_logger).and_return(rails_config)

        first = described_class.effective_config
        second = described_class.effective_config
        expect(first).to be(second)

        effective = first
        expect(effective.enabled).to be false
        expect(effective.subscriber_class).to be(rails_config.subscriber_class)
        expect(effective.logger).to be(rails_config.logger)
        expect(effective.tag).to eq("RailsTag")
      end

      it "handles missing Rails config attributes gracefully" do
        rails_config = double(respond_to?: true)
        allow(rails_config).to receive(:respond_to?).with(:enabled).and_return(false)
        allow(rails_config).to receive(:respond_to?).with(:subscriber_class).and_return(false)
        allow(rails_config).to receive(:respond_to?).with(:logger).and_return(false)
        allow(rails_config).to receive(:respond_to?).with(:tag).and_return(false)
        allow(Rails.application.config).to receive(:grape_rails_logger).and_return(rails_config)

        effective = described_class.effective_config
        expect(effective.enabled).to be true # Default from Config.new
        expect(effective.subscriber_class).to eq(GrapeRailsLogger::GrapeRequestLogSubscriber)
      end

      it "handles nil Rails config values" do
        rails_config = double(
          enabled: nil,
          subscriber_class: nil,
          logger: nil,
          tag: nil,
          respond_to?: true
        )
        allow(rails_config).to receive(:respond_to?).with(:enabled).and_return(true)
        allow(rails_config).to receive(:respond_to?).with(:subscriber_class).and_return(true)
        allow(rails_config).to receive(:respond_to?).with(:logger).and_return(true)
        allow(rails_config).to receive(:respond_to?).with(:tag).and_return(true)
        allow(Rails.application.config).to receive(:grape_rails_logger).and_return(rails_config)

        effective = described_class.effective_config
        expect(effective.enabled).to be_nil
        expect(effective.subscriber_class).to be_nil
        expect(effective.logger).to be_nil
        expect(effective.tag).to be_nil
      end
    end

    context "when Rails.application is nil" do
      before do
        allow(Rails).to receive(:application).and_return(nil)
      end

      it "falls back to module-level config" do
        effective = described_class.effective_config
        expect(effective).to be(described_class.config)
      end
    end

    context "when Rails config doesn't respond to grape_rails_logger" do
      before do
        allow(Rails).to receive(:application).and_return(Rails.application)
        allow(Rails.application.config).to receive(:respond_to?).with(:grape_rails_logger).and_return(false)
      end

      it "falls back to module-level config" do
        effective = described_class.effective_config
        expect(effective).to be(described_class.config)
      end
    end
  end

  describe GrapeRailsLogger::Config do
    describe "#initialize" do
      it "sets default values" do
        config = described_class.new
        expect(config.enabled).to be true
        expect(config.subscriber_class).to eq(GrapeRailsLogger::GrapeRequestLogSubscriber)
        expect(config.logger).to be_nil
        expect(config.tag).to eq("Grape")
      end
    end

    describe "attribute accessors" do
      it "allows setting and getting enabled" do
        config = described_class.new
        config.enabled = false
        expect(config.enabled).to be false
      end

      it "allows setting and getting subscriber_class" do
        config = described_class.new
        custom_class = Class.new
        config.subscriber_class = custom_class
        expect(config.subscriber_class).to be(custom_class)
      end

      it "allows setting and getting logger" do
        config = described_class.new
        logger = TestLogger.new
        config.logger = logger
        expect(config.logger).to be(logger)
      end

      it "allows setting and getting tag" do
        config = described_class.new
        config.tag = "Custom"
        expect(config.tag).to eq("Custom")
      end
    end
  end
end
