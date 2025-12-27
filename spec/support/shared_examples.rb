# frozen_string_literal: true

RSpec.shared_examples "API key validation" do
  describe "#initialize" do
    context "when API key is set" do
      it "initializes successfully" do
        expect { subject }.not_to raise_error
      end
    end

    context "when API key is not set" do
      before { ENV.delete("HATENA_API_KEY") }

      it "raises ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end

    context "when API key is empty" do
      before { ENV["HATENA_API_KEY"] = "" }

      it "raises ArgumentError" do
        expect { subject }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end
  end
end
