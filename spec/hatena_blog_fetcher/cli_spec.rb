# frozen_string_literal: true

require "spec_helper"
require_relative "../../hatena_blog_fetcher"

RSpec.describe HatenaBlogFetcher::CLI do
  let(:api_key) { "test_api_key_12345" }
  let(:cli) { described_class.new }

  before do
    ENV["HATENA_API_KEY"] = api_key
  end

  after do
    ENV.delete("HATENA_API_KEY")
  end

  describe ".run" do
    it "delegates to instance run method" do
      args = ["https://example.com/entry/test"]
      expect_any_instance_of(described_class).to receive(:run).with(args)

      described_class.run(args)
    end
  end

  describe "#run" do
    let(:entry_data) do
      {
        title: "Test Title",
        content: "Test Content",
        published: "2024-01-01 12:00:00",
        url: "https://example.com/entry/test"
      }
    end

    before do
      allow_any_instance_of(HatenaBlogFetcher).to receive(:fetch_entry).and_return(entry_data)
    end

    context "with valid URL" do
      it "fetches and outputs entry data in full format" do
        output = capture_stdout { cli.run(["https://example.com/entry/test"]) }
        expect(output).to include("Test Title")
        expect(output).to include("URL: https://example.com/entry/test")
        expect(output).to include("投稿日時: 2024-01-01 12:00:00")
        expect(output).to include("Test Content")
      end
    end

    context "with --raw option" do
      it "outputs only content" do
        expect { cli.run(["--raw", "https://example.com/entry/test"]) }.to output("Test Content\n").to_stdout
      end
    end

    context "with --title option" do
      it "outputs only title" do
        expect { cli.run(["--title", "https://example.com/entry/test"]) }.to output("Test Title\n").to_stdout
      end
    end

    context "with --date option" do
      it "outputs only datetime" do
        expect { cli.run(["--date", "https://example.com/entry/test"]) }.to output("2024-01-01 12:00:00\n").to_stdout
      end
    end

    context "with --url option" do
      it "outputs only url" do
        expect { cli.run(["--url", "https://example.com/entry/test"]) }.to output("https://example.com/entry/test\n").to_stdout
      end
    end

    context "with --help option" do
      it "displays help and exits" do
        expect { cli.run(["--help"]) }.to output(/使用方法/).to_stdout.and raise_error(SystemExit)
      end
    end

    context "with no arguments" do
      it "displays usage and exits with error" do
        expect { cli.run([]) }.to output(/使用方法/).to_stdout.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context "when error occurs" do
      before do
        allow_any_instance_of(HatenaBlogFetcher).to receive(:fetch_entry).and_raise("Test error")
      end

      it "outputs error message and exits" do
        expect do
          cli.run(["https://example.com/entry/test"])
        end.to output(/エラー: Test error/).to_stderr.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end
  end
end
