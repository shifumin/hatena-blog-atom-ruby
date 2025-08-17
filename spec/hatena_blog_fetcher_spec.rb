# frozen_string_literal: true

require "spec_helper"

RSpec.describe HatenaBlogFetcher do
  let(:api_key) { "test_api_key_12345" }
  let(:fetcher) { described_class.new }

  before do
    ENV["HATENA_API_KEY"] = api_key
  end

  after do
    ENV.delete("HATENA_API_KEY")
  end

  describe "#initialize" do
    context "when API key is set" do
      it "initializes successfully" do
        expect { fetcher }.not_to raise_error
      end
    end

    context "when API key is not set" do
      before { ENV.delete("HATENA_API_KEY") }

      it "raises ArgumentError" do
        expect { fetcher }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end

    context "when API key is empty" do
      before { ENV["HATENA_API_KEY"] = "" }

      it "raises ArgumentError" do
        expect { fetcher }.to raise_error(ArgumentError, /HATENA_API_KEY/)
      end
    end
  end

  describe "#fetch_entry" do
    let(:entry_url) { "https://shifumin.hatenadiary.com/entry/2024/01/01/123456" }
    let(:entry_api_url) { "#{HatenaBlogFetcher::API_ENDPOINT}/2024/01/01/123456" }
    let(:sample_atom_response) do
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
          <content type="text/x-markdown"># Test Content

        This is a test article with **Markdown** content.</content>
          <app:control>
            <app:draft>no</app:draft>
          </app:control>
        </entry>
      XML
    end

    context "with standard entry ID URL" do
      let(:entry_url) { "https://shifumin.hatenadiary.com/entry/20240101/1234567890" }
      let(:entry_api_url) { "#{HatenaBlogFetcher::API_ENDPOINT}/20240101/1234567890" }

      before do
        stub_request(:get, entry_api_url)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_atom_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "fetches and parses the entry correctly" do
        result = fetcher.fetch_entry(entry_url)

        expect(result[:title]).to eq("Test Article Title")
        expect(result[:content]).to include("# Test Content")
        expect(result[:content]).to include("**Markdown**")
        expect(result[:published]).to eq("2024-01-01 12:34:56")
        expect(result[:url]).to eq("https://shifumin.hatenadiary.com/entry/2024/01/01/123456")
      end
    end

    context "with date-based URL" do
      let(:entry_url) { "https://shifumin.hatenadiary.com/entry/2024/01/01/123456" }
      let(:list_response) do
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <link rel="next" href="https://blog.hatena.ne.jp/shifumin/shifumin.hatenadiary.com/atom/entry?page=2"/>
            <entry>
              <id>tag:blog.hatena.ne.jp,2013:blog-shifumin-17680117126972923446-13574176438046791234</id>
              <published>2024-01-01T12:34:56+09:00</published>
              <title>Test Article Title</title>
            </entry>
          </feed>
        XML
      end

      before do
        stub_request(:get, HatenaBlogFetcher::API_ENDPOINT)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: list_response, headers: { "Content-Type" => "application/atom+xml" })

        stub_request(:get, "#{HatenaBlogFetcher::API_ENDPOINT}/13574176438046791234")
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: sample_atom_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "finds and fetches the entry by date with apparent datetime" do
        result = fetcher.fetch_entry(entry_url)

        expect(result[:title]).to eq("Test Article Title")
        expect(result[:published]).to eq("2024-01-01 12:34:56") # 見かけ上の日時（URLから）
        expect(result[:url]).to eq("https://shifumin.hatenadiary.com/entry/2024/01/01/123456")
      end
    end

    context "when entry is not found" do
      let(:entry_url) { "https://shifumin.hatenadiary.com/entry/2024/12/31/235959" }
      let(:empty_list_response) do
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
          </feed>
        XML
      end

      before do
        stub_request(:get, HatenaBlogFetcher::API_ENDPOINT)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: empty_list_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "raises an error" do
        expect { fetcher.fetch_entry(entry_url) }.to raise_error(/記事が見つかりませんでした/)
      end
    end

    context "with invalid URL" do
      let(:entry_url) { "https://shifumin.hatenadiary.com/invalid/path" }

      it "raises ArgumentError" do
        expect { fetcher.fetch_entry(entry_url) }.to raise_error(ArgumentError, /無効なURL/)
      end
    end

    context "with content containing trailing whitespace" do
      let(:entry_url) { "https://shifumin.hatenadiary.com/entry/20240101/1234567890" }
      let(:entry_api_url) { "#{HatenaBlogFetcher::API_ENDPOINT}/20240101/1234567890" }
      let(:response_with_trailing_whitespace) do
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <entry xmlns="http://www.w3.org/2005/Atom">
            <link rel="alternate" type="text/html" href="https://shifumin.hatenadiary.com/entry/20240101/1234567890"/>
            <title>Test Article</title>
            <published>2024-01-01T12:00:00+09:00</published>
            <content type="text/x-markdown">Content with trailing spaces#{'    '}


          </content>
          </entry>
        XML
      end

      before do
        stub_request(:get, entry_api_url)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(
            status: 200,
            body: response_with_trailing_whitespace,
            headers: { "Content-Type" => "application/atom+xml" }
          )
      end

      it "removes trailing whitespace from content" do
        result = fetcher.fetch_entry(entry_url)
        expect(result[:content]).to eq("Content with trailing spaces")
        expect(result[:content]).not_to end_with(" ")
        expect(result[:content]).not_to end_with("\n")
        expect(result[:url]).not_to be_nil
      end
    end

    context "with XML missing fields" do
      let(:entry_url) { "https://shifumin.hatenadiary.com/entry/20240101/1234567890" }
      let(:entry_api_url) { "#{HatenaBlogFetcher::API_ENDPOINT}/20240101/1234567890" }

      context "when title is missing" do
        let(:response_without_title) do
          <<~XML
            <?xml version="1.0" encoding="utf-8"?>
            <entry xmlns="http://www.w3.org/2005/Atom">
              <link rel="alternate" type="text/html" href="https://shifumin.hatenadiary.com/entry/20240101/1234567890"/>
              <published>2024-01-01T12:00:00+09:00</published>
              <content type="text/x-markdown">Content without title</content>
            </entry>
          XML
        end

        before do
          stub_request(:get, entry_api_url)
            .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
            .to_return(status: 200, body: response_without_title, headers: { "Content-Type" => "application/atom+xml" })
        end

        it "returns default title" do
          result = fetcher.fetch_entry(entry_url)
          expect(result[:title]).to eq("タイトルなし")
        end
      end

      context "when content is missing" do
        let(:response_without_content) do
          <<~XML
            <?xml version="1.0" encoding="utf-8"?>
            <entry xmlns="http://www.w3.org/2005/Atom">
              <title>Title Only</title>
              <link rel="alternate" type="text/html" href="https://shifumin.hatenadiary.com/entry/20240101/1234567890"/>
              <published>2024-01-01T12:00:00+09:00</published>
            </entry>
          XML
        end

        before do
          stub_request(:get, entry_api_url)
            .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
            .to_return(
              status: 200,
              body: response_without_content,
              headers: { "Content-Type" => "application/atom+xml" }
            )
        end

        it "returns default content" do
          result = fetcher.fetch_entry(entry_url)
          expect(result[:content]).to eq("本文なし")
        end
      end

      context "when published date is missing" do
        let(:response_without_date) do
          <<~XML
            <?xml version="1.0" encoding="utf-8"?>
            <entry xmlns="http://www.w3.org/2005/Atom">
              <title>No Date</title>
              <link rel="alternate" type="text/html" href="https://shifumin.hatenadiary.com/entry/20240101/1234567890"/>
              <content type="text/x-markdown">Content without date</content>
            </entry>
          XML
        end

        before do
          stub_request(:get, entry_api_url)
            .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
            .to_return(status: 200, body: response_without_date, headers: { "Content-Type" => "application/atom+xml" })
        end

        it "returns default published date" do
          result = fetcher.fetch_entry(entry_url)
          expect(result[:published]).to eq("投稿日時不明")
        end
      end

      context "when alternate link is missing" do
        let(:response_without_alternate_link) do
          <<~XML
            <?xml version="1.0" encoding="utf-8"?>
            <entry xmlns="http://www.w3.org/2005/Atom">
              <id>tag:blog.hatena.ne.jp,2013:blog-shifumin-17680117126972923446-13574176438046791234</id>
              <title>No Link</title>
              <published>2024-01-01T12:00:00+09:00</published>
              <content type="text/x-markdown">Content without link</content>
            </entry>
          XML
        end

        before do
          stub_request(:get, entry_api_url)
            .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
            .to_return(
              status: 200,
              body: response_without_alternate_link,
              headers: { "Content-Type" => "application/atom+xml" }
            )
        end

        it "constructs URL from entry ID" do
          result = fetcher.fetch_entry(entry_url)
          expect(result[:url]).to eq("https://shifumin.hatenadiary.com/entry/13574176438046791234")
        end
      end
    end

    context "when API returns error" do
      let(:entry_url) { "https://shifumin.hatenadiary.com/entry/20240101/1234567890" }
      let(:entry_api_url) { "#{HatenaBlogFetcher::API_ENDPOINT}/20240101/1234567890" }

      context "with 401 Unauthorized" do
        before do
          stub_request(:get, entry_api_url)
            .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
            .to_return(status: 401, body: "Unauthorized", headers: {})
        end

        it "raises an error with status code" do
          expect { fetcher.fetch_entry(entry_url) }.to raise_error(/APIリクエストが失敗しました: 401/)
        end
      end

      context "with 404 Not Found" do
        before do
          stub_request(:get, entry_api_url)
            .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
            .to_return(status: 404, body: "Not Found", headers: {})
        end

        it "raises an error with status code" do
          expect { fetcher.fetch_entry(entry_url) }.to raise_error(/APIリクエストが失敗しました: 404/)
        end
      end

      context "with 500 Internal Server Error" do
        before do
          stub_request(:get, entry_api_url)
            .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
            .to_return(status: 500, body: "Internal Server Error", headers: {})
        end

        it "raises an error with status code and body" do
          expect { fetcher.fetch_entry(entry_url) }.to raise_error(/APIリクエストが失敗しました: 500.*Internal Server Error/m)
        end
      end
    end
  end

  describe "#find_entry_by_date" do
    let(:target_date) { "2024-01-01" }
    let(:time_part) { "123456" }

    let(:detail_response) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <entry xmlns="http://www.w3.org/2005/Atom">
          <link rel="alternate" type="text/html" href="https://shifumin.hatenadiary.com/entry/2024/01/01/123456"/>
          <title>Target Article</title>
          <published>2024-01-01T12:34:56+09:00</published>
          <content type="text/x-markdown">Found content</content>
        </entry>
      XML
    end
    let(:second_page_response) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <entry>
            <id>tag:blog.hatena.ne.jp,2013:blog-shifumin-17680117126972923446-13574176438046791234</id>
            <published>2024-01-01T12:34:56+09:00</published>
            <title>Target Article</title>
          </entry>
        </feed>
      XML
    end
    let(:list_response_with_pagination) do
      <<~XML
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
          <link rel="next" href="https://blog.hatena.ne.jp/shifumin/shifumin.hatenadiary.com/atom/entry?page=2"/>
          <entry>
            <id>tag:blog.hatena.ne.jp,2013:blog-shifumin-17680117126972923446-99999999999999999999</id>
            <published>2024-01-02T00:00:00+09:00</published>
            <title>Different Article</title>
          </entry>
        </feed>
      XML
    end

    context "when API returns error during pagination" do
      before do
        stub_request(:get, HatenaBlogFetcher::API_ENDPOINT)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 500, body: "Server Error", headers: {})
      end

      it "raises an error" do
        expect { fetcher.find_entry_by_date(target_date, time_part) }.to raise_error(/APIリクエストが失敗しました/)
      end
    end

    context "when entry is found on second page" do
      before do
        stub_request(:get, HatenaBlogFetcher::API_ENDPOINT)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(
            status: 200,
            body: list_response_with_pagination,
            headers: { "Content-Type" => "application/atom+xml" }
          )

        stub_request(:get, "https://blog.hatena.ne.jp/shifumin/shifumin.hatenadiary.com/atom/entry?page=2")
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: second_page_response, headers: { "Content-Type" => "application/atom+xml" })

        stub_request(:get, "#{HatenaBlogFetcher::API_ENDPOINT}/13574176438046791234")
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: detail_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "searches through multiple pages to find the entry" do
        result = fetcher.find_entry_by_date(target_date, time_part)

        expect(result).to be_a(Hash)
        expect(result[:title]).to eq("Target Article")
        expect(result[:content]).to eq("Found content")
        expect(result[:published]).to eq("2024-01-01 12:34:56")
        expect(result[:url]).to eq("https://shifumin.hatenadiary.com/entry/2024/01/01/123456")
      end
    end

    context "when entry is not found in any page" do
      let(:empty_response) do
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
          </feed>
        XML
      end

      before do
        stub_request(:get, HatenaBlogFetcher::API_ENDPOINT)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: empty_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "returns nil" do
        result = fetcher.find_entry_by_date(target_date, time_part)
        expect(result).to be_nil
      end
    end

    context "when time is within tolerance (edge case)" do
      let(:edge_case_response) do
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
              <id>tag:blog.hatena.ne.jp,2013:blog-shifumin-17680117126972923446-13574176438046791234</id>
              <published>2024-01-01T12:35:05+09:00</published>
              <title>Edge Case Article</title>
            </entry>
          </feed>
        XML
      end

      before do
        stub_request(:get, HatenaBlogFetcher::API_ENDPOINT)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: edge_case_response, headers: { "Content-Type" => "application/atom+xml" })

        stub_request(:get, "#{HatenaBlogFetcher::API_ENDPOINT}/13574176438046791234")
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(status: 200, body: detail_response, headers: { "Content-Type" => "application/atom+xml" })
      end

      it "matches entry with time within tolerance" do
        # 12:35:05 vs 12:35:05 = 0秒差（3600秒以内）
        result = fetcher.find_entry_by_date(target_date, "123505")
        expect(result).to be_a(Hash)
        expect(result[:url]).not_to be_nil
      end
    end

    context "when time is outside tolerance" do
      let(:outside_tolerance_response) do
        <<~XML
          <?xml version="1.0" encoding="utf-8"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <entry>
              <id>tag:blog.hatena.ne.jp,2013:blog-shifumin-17680117126972923446-13574176438046791234</id>
              <published>2024-01-01T13:40:00+09:00</published>
              <title>Outside Tolerance Article</title>
            </entry>
          </feed>
        XML
      end

      before do
        stub_request(:get, HatenaBlogFetcher::API_ENDPOINT)
          .with(headers: { "Accept" => "application/atom+xml", "X-WSSE" => /UsernameToken/ })
          .to_return(
            status: 200,
            body: outside_tolerance_response,
            headers: { "Content-Type" => "application/atom+xml" }
          )
      end

      it "does not match entry with time outside tolerance (1 hour)" do
        # 13:40:00 vs 12:34:56 = 3904秒差（3600秒の許容誤差を超える）
        result = fetcher.find_entry_by_date(target_date, "123456")
        expect(result).to be_nil
      end
    end
  end

  describe "#build_apparent_datetime (private)" do
    it "builds apparent datetime from URL components" do
      result = fetcher.send(:build_apparent_datetime, "2024", "01", "01", "123456")
      expect(result).to eq("2024-01-01 12:34:56")
    end

    it "handles time with less than 6 digits" do
      result = fetcher.send(:build_apparent_datetime, "2024", "01", "01", "1234")
      expect(result).to eq("2024-01-01 12:34:00")
    end

    it "handles time with only hours" do
      result = fetcher.send(:build_apparent_datetime, "2024", "01", "01", "12")
      expect(result).to eq("2024-01-01 12:00:00")
    end
  end
end
