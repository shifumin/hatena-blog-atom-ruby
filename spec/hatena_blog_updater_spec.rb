# frozen_string_literal: true

require "spec_helper"
require_relative "../hatena_blog_updater"

RSpec.describe HatenaBlogUpdater do
  let(:api_key) { "test_api_key_12345" }
  let(:updater) { described_class.new }
  let(:api_endpoint) { "https://blog.hatena.ne.jp/test-user/test-blog.hatenablog.com/atom/entry" }

  describe "#initialize" do
    context "when API key is set" do
      it "initializes successfully" do
        expect { updater }.not_to raise_error
      end
    end

    context "when API key is not set" do
      before { ENV.delete("HATENA_API_KEY") }

      it "raises ArgumentError" do
        expect { updater }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end

    context "when API key is empty" do
      before { ENV["HATENA_API_KEY"] = "" }

      it "raises ArgumentError" do
        expect { updater }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end
  end

  describe "#update_entry" do
    let(:entry_id) { "13574176438046791234" }
    let(:entry_api_url) { "#{api_endpoint}/#{entry_id}" }
    let(:sample_response) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <entry xmlns="http://www.w3.org/2005/Atom"
               xmlns:app="http://www.w3.org/2007/app">
          <id>tag:blog.hatena.ne.jp,2013:blog-test-user-17680117126972923446-#{entry_id}</id>
          <link rel="edit" href="https://blog.hatena.ne.jp/test-user/test-blog.hatenablog.com/atom/entry/#{entry_id}"/>
          <link rel="alternate" type="text/html" href="https://test-blog.hatenablog.com/entry/2024/01/01/123456"/>
          <author><name>test-user</name></author>
          <title>Updated Article Title</title>
          <published>2024-01-01T12:34:56+09:00</published>
          <updated>2024-01-02T10:00:00+09:00</updated>
          <content type="text/x-markdown"># Updated Content</content>
          <app:control>
            <app:draft>no</app:draft>
          </app:control>
        </entry>
      XML
    end

    # Helper method for common update call
    def perform_update(url_or_id: entry_id, title: "Test", content: "Content", draft: false, categories: [],
                       updated: nil)
      updater.update_entry(
        entry_url_or_id: url_or_id,
        title: title,
        content: content,
        draft: draft,
        categories: categories,
        updated: updated
      )
    end

    context "when updating with entry ID" do
      before do
        stub_request(:put, entry_api_url)
          .with(headers: { "Accept" => "application/atom+xml", "Content-Type" => "application/atom+xml",
                           "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "updates entry successfully" do
        result = perform_update(title: "Updated Title", content: "# Updated Content")
        expect(result[:title]).to eq("Updated Article Title")
      end

      it "sends correct XML with draft: no" do
        perform_update

        expect(WebMock).to(have_requested(:put, entry_api_url)
          .with { |req| req.body.include?("<app:draft>no</app:draft>") })
      end
    end

    context "when updating with draft: true" do
      before do
        stub_request(:put, entry_api_url)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "sends app:draft as yes" do
        perform_update(draft: true)

        expect(WebMock).to(have_requested(:put, entry_api_url)
          .with { |req| req.body.include?("<app:draft>yes</app:draft>") })
      end
    end

    context "when updating with categories" do
      before do
        stub_request(:put, entry_api_url)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "includes category elements in XML" do
        perform_update(categories: %w[Ruby API])

        expect(WebMock).to(have_requested(:put, entry_api_url)
          .with { |req| req.body.include?("<category term='Ruby'/>") && req.body.include?("<category term='API'/>") })
      end

      it "handles empty categories array" do
        perform_update(categories: [])

        expect(WebMock).to(have_requested(:put, entry_api_url)
          .with { |req| !req.body.include?("<category") })
      end

      it "handles single category" do
        perform_update(categories: ["Programming"])

        expect(WebMock).to(have_requested(:put, entry_api_url)
          .with { |req| req.body.include?("<category term='Programming'/>") })
      end
    end

    context "when updating with custom updated datetime" do
      before do
        stub_request(:put, entry_api_url)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "uses provided updated datetime" do
        custom_time = "2024-12-31T12:00:00+09:00"
        perform_update(updated: custom_time)

        expect(WebMock).to(have_requested(:put, entry_api_url)
          .with { |req| req.body.include?("<updated>#{custom_time}</updated>") })
      end

      it "uses current time when updated is nil" do
        perform_update(updated: nil)

        expect(WebMock).to(have_requested(:put, entry_api_url)
          .with { |req| req.body.include?("<updated>") })
      end
    end

    context "when updating with entry URL (entry ID format)" do
      let(:entry_url) { "https://test-blog.hatenablog.com/entry/20240101/#{entry_id}" }
      let(:url_entry_api) { "#{api_endpoint}/20240101/#{entry_id}" }

      before do
        stub_request(:put, url_entry_api)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "extracts entry ID from URL and updates" do
        result = perform_update(url_or_id: entry_url, title: "Updated Title")
        expect(result[:title]).to eq("Updated Article Title")
      end
    end

    context "when updating with date-based URL" do
      let(:date_based_url) { "https://test-blog.hatenablog.com/entry/2024/01/01/123456" }
      let(:entry_list_response) do
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
              <id>tag:blog.hatena.ne.jp,2013:blog-test-user-17680117126972923446-#{entry_id}</id>
              <link rel="alternate" type="text/html" href="https://test-blog.hatenablog.com/entry/2024/01/01/123456"/>
              <published>2024-01-01T12:34:56+09:00</published>
              <title>Test Entry</title>
            </entry>
          </feed>
        XML
      end

      before do
        stub_request(:get, api_endpoint)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: entry_list_response, headers: { "Content-Type" => "application/atom+xml" })

        stub_request(:put, entry_api_url)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "searches for entry and updates" do
        result = perform_update(url_or_id: date_based_url, title: "Updated Title")
        expect(result[:title]).to eq("Updated Article Title")
      end
    end

    context "when parsing response" do
      let(:result) { perform_update }

      before do
        stub_request(:put, entry_api_url)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "extracts title from response" do
        expect(result[:title]).to eq("Updated Article Title")
      end

      it "extracts url from alternate link" do
        expect(result[:url]).to eq("https://test-blog.hatenablog.com/entry/2024/01/01/123456")
      end

      it "builds edit_url from entry id" do
        expect(result[:edit_url]).to eq("https://blog.hatena.ne.jp/test-user/test-blog.hatenablog.com/edit?entry=#{entry_id}")
      end

      it "extracts published date" do
        expect(result[:published]).to eq("2024-01-01T12:34:56+09:00")
      end
    end

    context "when API returns error" do
      context "with 401 Unauthorized" do
        before do
          stub_request(:put, entry_api_url)
            .with(headers: { "X-WSSE" => /UsernameToken/ })
            .to_return(status: 401, body: "Unauthorized", headers: {})
        end

        it "raises an error with status code" do
          expect { perform_update }.to raise_error(/APIリクエストが失敗しました: 401/)
        end
      end

      context "with 404 Not Found" do
        before do
          stub_request(:put, entry_api_url)
            .with(headers: { "X-WSSE" => /UsernameToken/ })
            .to_return(status: 404, body: "Not Found", headers: {})
        end

        it "raises an error with status code" do
          expect { perform_update }.to raise_error(/APIリクエストが失敗しました: 404/)
        end
      end

      context "with 500 Internal Server Error" do
        before do
          stub_request(:put, entry_api_url)
            .with(headers: { "X-WSSE" => /UsernameToken/ })
            .to_return(status: 500, body: "Internal Server Error", headers: {})
        end

        it "raises an error with status code and body" do
          expect { perform_update }.to raise_error(/APIリクエストが失敗しました: 500.*Internal Server Error/m)
        end
      end
    end

    context "when date-based URL entry is not found" do
      let(:date_based_url) { "https://test-blog.hatenablog.com/entry/2024/01/01/999999" }
      let(:empty_response) { "<?xml version=\"1.0\"?>\n<feed xmlns=\"http://www.w3.org/2005/Atom\"></feed>" }

      before do
        stub_request(:get, api_endpoint)
          .with(headers: { "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: empty_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "raises an error" do
        expect { perform_update(url_or_id: date_based_url) }.to raise_error(/指定された日付の記事が見つかりませんでした/)
      end
    end
  end
end
