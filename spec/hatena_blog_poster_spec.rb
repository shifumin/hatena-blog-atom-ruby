# frozen_string_literal: true

require "spec_helper"
require_relative "../hatena_blog_poster"

RSpec.describe HatenaBlogPoster do
  let(:api_key) { "test_api_key_12345" }
  let(:poster) { described_class.new }

  before do
    ENV["HATENA_API_KEY"] = api_key
  end

  after do
    ENV.delete("HATENA_API_KEY")
  end

  describe "#initialize" do
    context "when API key is set" do
      it "initializes successfully" do
        expect { poster }.not_to raise_error
      end
    end

    context "when API key is not set" do
      before { ENV.delete("HATENA_API_KEY") }

      it "raises ArgumentError" do
        expect { poster }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end

    context "when API key is empty" do
      before { ENV["HATENA_API_KEY"] = "" }

      it "raises ArgumentError" do
        expect { poster }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end
  end

  describe "#post_entry" do
    let(:sample_response) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <entry xmlns="http://www.w3.org/2005/Atom"
               xmlns:app="http://www.w3.org/2007/app">
          <id>tag:blog.hatena.ne.jp,2013:blog-shifumin-17680117126972923446-13574176438046791234</id>
          <link rel="edit" href="https://blog.hatena.ne.jp/shifumin/shifumin.hatenadiary.com/atom/entry/13574176438046791234"/>
          <link rel="alternate" type="text/html" href="https://shifumin.hatenadiary.com/entry/2024/01/01/123456"/>
          <author><name>shifumin</name></author>
          <title>Test Article Title</title>
          <published>2024-01-01T12:34:56+09:00</published>
          <updated>2024-01-01T12:34:56+09:00</updated>
          <content type="text/x-markdown"># Test Content</content>
          <app:control>
            <app:draft>yes</app:draft>
          </app:control>
        </entry>
      XML
    end

    context "with draft post" do
      before do
        stub_request(:post, HatenaBlogPoster::API_ENDPOINT)
          .with(
            headers: {
              "Accept" => "application/atom+xml",
              "Content-Type" => "application/atom+xml",
              "X-WSSE" => /UsernameToken/
            }
          )
          .to_return(status: 201, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "posts entry as draft" do
        result = poster.post_entry(title: "Test", content: "Content", draft: true)
        expect(result[:title]).to eq("Test Article Title")
      end

      it "sends app:draft as yes" do
        poster.post_entry(title: "Test", content: "Content", draft: true)

        expect(WebMock).to(have_requested(:post, HatenaBlogPoster::API_ENDPOINT)
          .with { |req| req.body.include?("<app:draft>yes</app:draft>") })
      end
    end

    context "with published post" do
      before do
        stub_request(:post, HatenaBlogPoster::API_ENDPOINT)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 201, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "sends app:draft as no" do
        poster.post_entry(title: "Test", content: "Content", draft: false)

        expect(WebMock).to(have_requested(:post, HatenaBlogPoster::API_ENDPOINT)
          .with { |req| req.body.include?("<app:draft>no</app:draft>") })
      end
    end

    context "when parsing response" do
      before do
        stub_request(:post, HatenaBlogPoster::API_ENDPOINT)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 201, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "extracts title from response" do
        result = poster.post_entry(title: "Test", content: "Content", draft: true)
        expect(result[:title]).to eq("Test Article Title")
      end

      it "extracts url from alternate link" do
        result = poster.post_entry(title: "Test", content: "Content", draft: true)
        expect(result[:url]).to eq("https://shifumin.hatenadiary.com/entry/2024/01/01/123456")
      end

      it "builds edit_url from entry id" do
        result = poster.post_entry(title: "Test", content: "Content", draft: true)
        expect(result[:edit_url]).to eq("https://blog.hatena.ne.jp/shifumin/shifumin.hatenadiary.com/edit?entry=13574176438046791234")
      end

      it "extracts published date" do
        result = poster.post_entry(title: "Test", content: "Content", draft: true)
        expect(result[:published]).to eq("2024-01-01T12:34:56+09:00")
      end
    end

    context "when API returns error" do
      context "with 401 Unauthorized" do
        before do
          stub_request(:post, HatenaBlogPoster::API_ENDPOINT)
            .with(headers: { "X-WSSE" => /UsernameToken/ })
            .to_return(status: 401, body: "Unauthorized", headers: {})
        end

        it "raises an error with status code" do
          expect { poster.post_entry(title: "Test", content: "Content", draft: true) }
            .to raise_error(/APIリクエストが失敗しました: 401/)
        end
      end

      context "with 500 Internal Server Error" do
        before do
          stub_request(:post, HatenaBlogPoster::API_ENDPOINT)
            .with(headers: { "X-WSSE" => /UsernameToken/ })
            .to_return(status: 500, body: "Internal Server Error", headers: {})
        end

        it "raises an error with status code and body" do
          expect { poster.post_entry(title: "Test", content: "Content", draft: true) }
            .to raise_error(/APIリクエストが失敗しました: 500.*Internal Server Error/m)
        end
      end
    end
  end
end
