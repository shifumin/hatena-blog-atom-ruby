#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "uri"
require "rexml/document"
require "digest/sha1"
require "base64"
require "securerandom"
require "time"
require "optparse"

class HatenaBlogFetcher
  HATENA_ID = "shifumin"
  BLOG_ID = "shifumin.hatenadiary.com"
  API_ENDPOINT = "https://blog.hatena.ne.jp/#{HATENA_ID}/#{BLOG_ID}/atom/entry".freeze

  def initialize
    @api_key = ENV.fetch("HATENA_API_KEY", nil)
    validate_api_key!
  end

  def fetch_entry(entry_url)
    if date_based_url?(entry_url)
      fetch_entry_by_date(entry_url)
    else
      fetch_entry_by_id(entry_url)
    end
  end

  def find_entry_by_date(target_date, time_part)
    matching_entry = search_entry_in_pages(target_date, time_part)
    return nil unless matching_entry

    fetch_entry_details(matching_entry)
  end

  private

  def date_based_url?(url)
    url.match?(%r{/entry/(\d{4})/(\d{2})/(\d{2})/(\d+)})
  end

  def fetch_entry_by_date(entry_url)
    date_match = entry_url.match(%r{/entry/(\d{4})/(\d{2})/(\d{2})/(\d+)})
    year, month, day, time = date_match[1..4]
    target_date = "#{year}-#{month}-#{day}"

    entry_data = find_entry_by_date(target_date, time)
    return entry_data if entry_data

    raise "指定された日付の記事が見つかりませんでした: #{entry_url}"
  end

  def fetch_entry_by_id(entry_url)
    entry_id = extract_entry_id(entry_url)
    entry_api_url = "#{API_ENDPOINT}/#{entry_id}"

    response = get_with_wsse_auth(entry_api_url)
    parse_entry(response.body)
  end

  def validate_api_key!
    return unless @api_key.nil? || @api_key.empty?

    raise ArgumentError, "環境変数 HATENA_API_KEY が設定されていません。\n" \
                         "export HATENA_API_KEY='あなたのAPIキー' を実行してください。"
  end

  def extract_entry_id(url)
    # URLパターン例:
    # https://shifumin.hatenadiary.com/entry/2024/01/01/123456
    # https://shifumin.hatenadiary.com/entry/20240101/1234567890

    uri = URI.parse(url)
    path_parts = uri.path.split("/")

    entry_index = path_parts.index("entry")
    raise ArgumentError, "無効なURLです: #{url}" unless entry_index

    # entry以降のパスを結合してIDとする
    path_parts[(entry_index + 1)..].join("/")
  end

  def create_wsse_header
    # ランダムなnonceを生成（バイナリ）
    nonce = SecureRandom.random_bytes(20)
    # 現在時刻をISO8601形式で取得
    created = Time.now.utc.iso8601

    # ダイジェスト計算: SHA1(nonce + created + password)
    # バイナリエンコーディングで文字列を作成
    digest_input = String.new(encoding: Encoding::BINARY)
    digest_input << nonce
    digest_input << created
    digest_input << @api_key

    password_digest = Base64.strict_encode64(
      Digest::SHA1.digest(digest_input)
    )

    # nonceをBase64エンコード
    nonce_base64 = Base64.strict_encode64(nonce)

    # WSSEヘッダーを組み立て
    "UsernameToken Username=\"#{HATENA_ID}\", " \
      "PasswordDigest=\"#{password_digest}\", " \
      "Nonce=\"#{nonce_base64}\", " \
      "Created=\"#{created}\""
  end

  def get_with_wsse_auth(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    request["X-WSSE"] = create_wsse_header
    request["Accept"] = "application/atom+xml"

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      body = response.body.to_s.dup.force_encoding("UTF-8")
      raise "APIリクエストが失敗しました: #{response.code} #{response.message}\n#{body}"
    end

    response
  end

  def search_entry_in_pages(target_date, time_part)
    max_pages = 100
    page_count = 0
    next_url = API_ENDPOINT

    while next_url && page_count < max_pages
      page_count += 1
      response = get_with_wsse_auth(next_url)
      doc = REXML::Document.new(response.body)

      matching_entry = find_matching_entry_in_page(doc, target_date, time_part)
      return matching_entry if matching_entry

      next_url = get_next_page_url(doc)
      warn "Fetching next page: #{next_url}" if next_url
    end

    nil
  end

  def find_matching_entry_in_page(doc, target_date, time_part)
    doc.elements.each("feed/entry") do |entry|
      next unless entry_matches_date?(entry, target_date, time_part)

      entry_id = extract_entry_id_from_element(entry)
      return entry_id if entry_id
    end
    nil
  end

  def entry_matches_date?(entry, target_date, time_part)
    published = entry.elements["published"]&.text
    return false unless published

    published_date = Time.parse(published).strftime("%Y-%m-%d")
    published_time = Time.parse(published).strftime("%H%M%S")

    return false unless published_date == target_date

    time_matches?(published_time, time_part)
  end

  def time_matches?(published_time, target_time, tolerance_seconds = 10)
    published_seconds = published_time.to_i
    target_seconds = target_time.to_i
    (published_seconds - target_seconds).abs <= tolerance_seconds
  end

  def extract_entry_id_from_element(entry)
    id_element = entry.elements["id"]
    return nil unless id_element

    id_text = id_element.text
    return nil unless id_text

    id_text.split("-").last
  end

  def fetch_entry_details(entry_id)
    entry_api_url = "#{API_ENDPOINT}/#{entry_id}"
    detail_response = get_with_wsse_auth(entry_api_url)
    parse_entry(detail_response.body)
  end

  def get_next_page_url(doc)
    next_link = doc.elements['feed/link[@rel="next"]']
    next_link&.attributes&.[]("href")
  end

  def parse_entry(xml_body)
    doc = REXML::Document.new(xml_body)
    entry = doc.root

    {
      title: extract_title_from_entry(entry),
      content: extract_content_from_entry(entry),
      published: extract_published_date_from_entry(entry),
      url: extract_url_from_entry(entry)
    }
  end

  def extract_title_from_entry(entry)
    entry.elements["title"]&.text || "タイトルなし"
  end

  def extract_content_from_entry(entry)
    content_element = entry.elements["content"]
    return "本文なし" unless content_element

    content_element.text&.rstrip || "本文なし"
  end

  def extract_published_date_from_entry(entry)
    published = entry.elements["published"]&.text
    return "投稿日時不明" unless published

    Time.parse(published).strftime("%Y-%m-%d %H:%M:%S")
  end

  def extract_url_from_entry(entry)
    # alternateリンクを探す（ブログ記事のURL）
    alternate_link = entry.elements['link[@rel="alternate"]']
    return alternate_link.attributes["href"] if alternate_link&.attributes&.[]("href")

    # alternateがない場合はidから構築
    id_element = entry.elements["id"]
    return nil unless id_element

    id_text = id_element.text
    return nil unless id_text

    entry_id = id_text.split("-").last
    # デフォルトのURL形式で構築
    "https://#{BLOG_ID}/entry/#{entry_id}"
  end
end

class CommandLineInterface
  def self.run(args)
    new.run(args)
  end

  def run(args)
    options = parse_options(args)
    url = validate_arguments(args)

    entry_data = fetch_entry(url)
    output_result(entry_data, options)
  rescue StandardError => e
    handle_error(e)
  end

  private

  def parse_options(args)
    options = {}
    parser = create_option_parser(options)
    parser.parse!(args)
    options
  end

  def create_option_parser(options)
    OptionParser.new do |opts|
      opts.banner = "使用方法: #{$PROGRAM_NAME} [オプション] URL"
      opts.separator ""
      opts.separator "はてなブログの記事情報を取得します"
      opts.separator ""
      opts.separator "オプション:"

      define_options(opts, options)
    end
  end

  def define_options(opts, options)
    opts.on("-h", "--help", "このヘルプを表示") do
      puts opts
      exit
    end

    opts.on("-r", "--raw", "生のMarkdown本文のみを出力") do
      options[:raw] = true
    end

    opts.on("-t", "--title", "タイトルのみを出力") do
      options[:title_only] = true
    end

    opts.on("-d", "--date", "投稿日時のみを出力") do
      options[:date_only] = true
    end

    opts.on("-u", "--url", "URLのみを出力") do
      options[:url_only] = true
    end
  end

  def validate_arguments(args)
    if args.empty?
      parser = create_option_parser({})
      puts parser
      exit 1
    end
    args[0]
  end

  def fetch_entry(url)
    fetcher = HatenaBlogFetcher.new
    fetcher.fetch_entry(url)
  end

  def output_result(entry_data, options)
    if options[:raw]
      output_raw_content(entry_data)
    elsif options[:title_only]
      output_title(entry_data)
    elsif options[:date_only]
      output_date(entry_data)
    elsif options[:url_only]
      output_url(entry_data)
    else
      output_full_format(entry_data)
    end
  end

  def output_raw_content(entry_data)
    puts entry_data[:content]
  end

  def output_title(entry_data)
    puts entry_data[:title]
  end

  def output_url(entry_data)
    puts entry_data[:url]
  end

  def output_date(entry_data)
    puts entry_data[:published]
  end

  def output_full_format(entry_data)
    puts "=" * 60
    puts "タイトル: #{entry_data[:title]}"
    puts "投稿日時: #{entry_data[:published]}"
    puts "URL: #{entry_data[:url]}"
    puts "=" * 60
    puts "本文（Markdown）:"
    puts "-" * 60
    puts entry_data[:content]
    puts "=" * 60
  end

  def handle_error(error)
    warn "エラー: #{error.message}"
    warn error.backtrace
    exit 1
  end
end

def main
  CommandLineInterface.run(ARGV)
end

main if __FILE__ == $PROGRAM_NAME
