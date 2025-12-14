#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "uri"
require "rexml/document"
require "digest/sha1"
require "base64"
require "securerandom"
require "time"
require "date"
require "optparse"
require "openssl"

# はてなブログAtomPub APIを使用してブログ記事を取得するクラス
#
# @example 基本的な使用方法
#   fetcher = HatenaBlogFetcher.new
#   entry = fetcher.fetch_entry("https://example.hatenadiary.com/entry/2024/01/01/120000")
#   puts entry[:title]
#
# @see https://developer.hatena.ne.jp/ja/documents/blog/apis/atom
class HatenaBlogFetcher
  # @return [String] はてなID
  HATENA_ID = "shifumin"
  # @return [String] ブログID（ドメイン）
  BLOG_ID = "shifumin.hatenadiary.com"
  # @return [String] AtomPub APIエンドポイント
  API_ENDPOINT = "https://blog.hatena.ne.jp/#{HATENA_ID}/#{BLOG_ID}/atom/entry".freeze

  # HatenaBlogFetcherの新しいインスタンスを作成する
  #
  # @raise [ArgumentError] 環境変数HATENA_API_KEYが設定されていない場合
  def initialize
    @api_key = ENV.fetch("HATENA_API_KEY", nil)
    validate_api_key!
  end

  # 指定されたURLからブログ記事を取得する
  #
  # @param entry_url [String] 記事のURL（日付ベースまたはエントリーID形式）
  # @return [Hash] 記事データ
  # @option return [String] :title 記事タイトル
  # @option return [String] :content 記事本文（Markdown）
  # @option return [String] :published 投稿日時（YYYY-MM-DD HH:MM:SS形式）
  # @option return [String] :url 記事URL
  # @raise [RuntimeError] 記事が見つからない場合
  # @raise [RuntimeError] APIリクエストが失敗した場合
  def fetch_entry(entry_url)
    if date_based_url?(entry_url)
      fetch_entry_by_date(entry_url)
    else
      fetch_entry_by_id(entry_url)
    end
  end

  # 日付と時刻から記事を検索する
  #
  # @param target_date [String] 検索対象の日付（YYYY-MM-DD形式）
  # @param time_part [String] 検索対象の時刻（HHMMSS形式）
  # @return [Hash, nil] 記事データ、見つからない場合はnil
  def find_entry_by_date(target_date, time_part)
    matching_entry = search_entry_in_pages(target_date, time_part)
    return nil unless matching_entry

    fetch_entry_details(matching_entry)
  end

  private

  # URLが日付ベース形式かどうかを判定する
  #
  # @param url [String] 判定対象のURL
  # @return [Boolean] 日付ベース形式の場合true
  def date_based_url?(url)
    url.match?(%r{/entry/(\d{4})/(\d{2})/(\d{2})/(\d+)})
  end

  # 日付ベースURLから記事を取得する
  #
  # @param entry_url [String] 日付ベース形式の記事URL
  # @return [Hash] 記事データ
  # @raise [RuntimeError] 記事が見つからない場合
  def fetch_entry_by_date(entry_url)
    date_match = entry_url.match(%r{/entry/(\d{4})/(\d{2})/(\d{2})/(\d+)})
    year, month, day, time = date_match[1..4]
    target_date = "#{year}-#{month}-#{day}"

    entry_data = find_entry_by_date(target_date, time)
    if entry_data
      # URLから見かけ上の日時を生成して上書き
      apparent_datetime = build_apparent_datetime(year, month, day, time)
      entry_data[:published] = apparent_datetime
      return entry_data
    end

    raise "指定された日付の記事が見つかりませんでした: #{entry_url}"
  end

  # エントリーIDから記事を取得する
  #
  # @param entry_url [String] 記事URL
  # @return [Hash] 記事データ
  # @raise [RuntimeError] APIリクエストが失敗した場合
  def fetch_entry_by_id(entry_url)
    entry_id = extract_entry_id(entry_url)
    entry_api_url = "#{API_ENDPOINT}/#{entry_id}"

    response = get_with_wsse_auth(entry_api_url)
    parse_entry(response.body)
  end

  # APIキーの存在を検証する
  #
  # @raise [ArgumentError] APIキーが未設定または空の場合
  def validate_api_key!
    return unless @api_key.nil? || @api_key.empty?

    raise ArgumentError, "環境変数 HATENA_API_KEY が設定されていません。\n" \
                         "export HATENA_API_KEY='あなたのAPIキー' を実行してください。"
  end

  # URLからエントリーIDを抽出する
  #
  # @param url [String] 記事URL
  # @return [String] エントリーID
  # @raise [ArgumentError] 無効なURL形式の場合
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

  # WSSE認証ヘッダーを生成する
  #
  # @return [String] X-WSSEヘッダー値
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

  # WSSE認証付きでHTTP GETリクエストを実行する
  #
  # @param url [String] リクエスト先URL
  # @return [Net::HTTPResponse] HTTPレスポンス
  # @raise [RuntimeError] APIリクエストが失敗した場合
  def get_with_wsse_auth(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = create_cert_store

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

  # SSL証明書ストアを作成する
  #
  # CRLチェックは無効化されているが、基本的な証明書検証は維持される
  #
  # @return [OpenSSL::X509::Store] 証明書ストア
  def create_cert_store
    store = OpenSSL::X509::Store.new
    store.set_default_paths
    # CRLチェックはデフォルトで無効（明示的に有効化しない）
    # 証明書の基本的な検証（ホスト名、有効期限、信頼チェーン）は維持される
    store
  end

  # ページを巡回して記事を検索する
  #
  # @param target_date [String] 検索対象の日付（YYYY-MM-DD形式）
  # @param time_part [String] 検索対象の時刻（HHMMSS形式）
  # @return [String, nil] エントリーID、見つからない場合はnil
  def search_entry_in_pages(target_date, time_part)
    max_pages = 100
    page_count = 0
    next_url = API_ENDPOINT
    candidates = []

    while next_url && page_count < max_pages
      page_count += 1
      response = get_with_wsse_auth(next_url)
      doc = REXML::Document.new(response.body)

      # 候補を収集
      page_candidates = find_matching_entries_in_page(doc, target_date, time_part)
      candidates.concat(page_candidates)

      # 完全一致があれば即座に返す
      perfect_match = candidates.find { |c| c[:score].zero? }
      return perfect_match[:entry_id] if perfect_match

      next_url = get_next_page_url(doc)
    end

    # 最もスコアが低い（最も一致度が高い）候補を返す
    return nil if candidates.empty?

    best_candidate = candidates.min_by { |c| c[:score] }
    best_candidate[:entry_id]
  end

  # 1ページ内で一致する記事を検索する
  #
  # @param doc [REXML::Document] XMLドキュメント
  # @param target_date [String] 検索対象の日付（YYYY-MM-DD形式）
  # @param time_part [String] 検索対象の時刻（HHMMSS形式）
  # @return [Array<Hash>] 候補記事の配列（entry_id, score, titleを含む）
  def find_matching_entries_in_page(doc, target_date, time_part)
    candidates = []
    doc.elements.each("feed/entry") do |entry|
      score = calculate_entry_match_score(entry, target_date, time_part)
      next if score.nil?

      entry_id = extract_entry_id_from_element(entry)
      next unless entry_id

      title = entry.elements["title"]&.text || ""
      candidates << { entry_id: entry_id, score: score, title: title }
    end
    candidates
  end

  # 記事のマッチスコアを計算する
  #
  # スコアが低いほど一致度が高い。完全一致は0を返す。
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @param target_date [String] 検索対象の日付（YYYY-MM-DD形式）
  # @param time_part [String] 検索対象の時刻（HHMMSS形式）
  # @return [Integer, nil] マッチスコア、候補外の場合はnil
  def calculate_entry_match_score(entry, target_date, time_part)
    published = entry.elements["published"]&.text
    return nil unless published

    published_datetime = parse_published_datetime(published)

    # 記事URLを確認
    entry_url = extract_url_from_entry_element(entry)
    if entry_url&.include?("/entry/#{target_date.tr('-', '/')}/#{time_part}")
      # URLが完全に一致する場合は最優先
      return 0
    end

    # 日付の差を計算
    date_diff = calculate_date_diff(published_datetime[:date], target_date)
    return nil if date_diff > 7 # 7日以上離れていたら候補から除外

    # 時刻の差を計算
    time_diff = calculate_time_diff(published_datetime[:time], time_part)
    return nil if time_diff > 3600 # 1時間（3600秒）を超える差がある場合は候補から除外

    # スコアを計算（低いほど良い）
    (date_diff * 86_400) + time_diff # 日付の差を秒に換算して加算
  end

  # 日付の差を計算する
  #
  # @param published_date_str [String] 投稿日（YYYY-MM-DD形式）
  # @param target_date_str [String] 検索対象日（YYYY-MM-DD形式）
  # @return [Integer] 日数の差（絶対値）
  def calculate_date_diff(published_date_str, target_date_str)
    published_date = Date.parse(published_date_str)
    target_date = Date.parse(target_date_str)
    (published_date - target_date).abs
  end

  # 時刻の差を計算する
  #
  # @param published_time [String] 投稿時刻（HHMMSS形式）
  # @param target_time [String] 検索対象時刻（HHMMSS形式）
  # @return [Integer] 秒数の差（絶対値）
  def calculate_time_diff(published_time, target_time)
    published_seconds = convert_hhmmss_to_seconds(published_time)
    target_seconds = convert_hhmmss_to_seconds(target_time)
    (published_seconds - target_seconds).abs
  end

  # 投稿日時文字列をパースする
  #
  # @param published_str [String] ISO8601形式の投稿日時
  # @return [Hash] 日付と時刻を含むハッシュ
  # @option return [String] :date 日付（YYYY-MM-DD形式）
  # @option return [String] :time 時刻（HHMMSS形式）
  def parse_published_datetime(published_str)
    parsed_time = Time.parse(published_str)
    {
      date: parsed_time.strftime("%Y-%m-%d"),
      time: parsed_time.strftime("%H%M%S")
    }
  end

  # HHMMSS形式の時刻を秒数に変換する
  #
  # @param time_str [String] HHMMSS形式の時刻
  # @return [Integer] 0時からの秒数
  def convert_hhmmss_to_seconds(time_str)
    hour = time_str[0, 2].to_i
    min = time_str[2, 2].to_i
    sec = time_str[4, 2].to_i
    (hour * 3600) + (min * 60) + sec
  end

  # URLから見かけ上の日時を構築する
  #
  # @param year [String] 年（4桁）
  # @param month [String] 月（2桁）
  # @param day [String] 日（2桁）
  # @param time_str [String] 時刻（HHMMSS形式、6桁未満の場合は0で埋める）
  # @return [String] 日時文字列（YYYY-MM-DD HH:MM:SS形式）
  def build_apparent_datetime(year, month, day, time_str)
    # HHMMSS形式から時:分:秒を抽出（不足分は0で埋める）
    padded_time = time_str.ljust(6, "0")
    hour = padded_time[0, 2]
    min = padded_time[2, 2]
    sec = padded_time[4, 2]

    # 見かけ上の日時を構築
    "#{year}-#{month}-#{day} #{hour}:#{min}:#{sec}"
  end

  # XML要素からエントリーIDを抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String, nil] エントリーID、取得できない場合はnil
  def extract_entry_id_from_element(entry)
    id_element = entry.elements["id"]
    return nil unless id_element

    id_text = id_element.text
    return nil unless id_text

    id_text.split("-").last
  end

  # XML要素から記事URLを抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String, nil] 記事URL、取得できない場合はnil
  def extract_url_from_entry_element(entry)
    # link要素からalternateリンクを探す
    link = entry.elements['link[@rel="alternate"]']
    return link.attributes["href"] if link&.attributes&.[]("href")

    # alternateリンクがない場合はidから構築
    id_element = entry.elements["id"]
    return nil unless id_element&.text

    entry_id = id_element.text.split("-").last
    "https://#{BLOG_ID}/entry/#{entry_id}"
  end

  # エントリーIDから記事詳細を取得する
  #
  # @param entry_id [String] エントリーID
  # @return [Hash] 記事データ
  def fetch_entry_details(entry_id)
    entry_api_url = "#{API_ENDPOINT}/#{entry_id}"
    detail_response = get_with_wsse_auth(entry_api_url)
    parse_entry(detail_response.body)
  end

  # 次ページのURLを取得する
  #
  # @param doc [REXML::Document] XMLドキュメント
  # @return [String, nil] 次ページのURL、存在しない場合はnil
  def get_next_page_url(doc)
    next_link = doc.elements['feed/link[@rel="next"]']
    next_link&.attributes&.[]("href")
  end

  # XMLレスポンスをパースして記事データを抽出する
  #
  # @param xml_body [String] XMLレスポンス本文
  # @return [Hash] 記事データ
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

  # 記事からタイトルを抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String] タイトル（取得できない場合は"タイトルなし"）
  def extract_title_from_entry(entry)
    entry.elements["title"]&.text || "タイトルなし"
  end

  # 記事から本文を抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String] 本文（取得できない場合は"本文なし"）
  def extract_content_from_entry(entry)
    content_element = entry.elements["content"]
    return "本文なし" unless content_element

    content_element.text&.rstrip || "本文なし"
  end

  # 記事から投稿日時を抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String] 投稿日時（YYYY-MM-DD HH:MM:SS形式、取得できない場合は"投稿日時不明"）
  def extract_published_date_from_entry(entry)
    published = entry.elements["published"]&.text
    return "投稿日時不明" unless published

    Time.parse(published).strftime("%Y-%m-%d %H:%M:%S")
  end

  # 記事からURLを抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String, nil] 記事URL
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

class HatenaBlogFetcher
  # コマンドラインインターフェースを提供するクラス
  #
  # @example 基本的な使用方法
  #   HatenaBlogFetcher::CLI.run(ARGV)
  class CLI
    # CLIを実行する
    #
    # @param args [Array<String>] コマンドライン引数
    # @return [void]
    def self.run(args)
      new.run(args)
    end

    # インスタンスメソッドとしてCLIを実行する
    #
    # @param args [Array<String>] コマンドライン引数
    # @return [void]
    def run(args)
      options = parse_options(args)
      url = validate_arguments(args)

      entry_data = fetch_entry(url)
      output_result(entry_data, options)
    rescue StandardError => e
      handle_error(e)
    end

    private

    # コマンドラインオプションをパースする
    #
    # @param args [Array<String>] コマンドライン引数
    # @return [Hash] パースされたオプション
    def parse_options(args)
      options = {}
      parser = create_option_parser(options)
      parser.parse!(args)
      options
    end

    # OptionParserインスタンスを作成する
    #
    # @param options [Hash] オプションを格納するハッシュ
    # @return [OptionParser] 設定済みのOptionParser
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

    # オプションを定義する
    #
    # @param opts [OptionParser] OptionParserインスタンス
    # @param options [Hash] オプションを格納するハッシュ
    # @return [void]
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

    # 引数を検証する
    #
    # @param args [Array<String>] コマンドライン引数
    # @return [String] 検証済みのURL
    def validate_arguments(args)
      if args.empty?
        parser = create_option_parser({})
        puts parser
        exit 1
      end
      args[0]
    end

    # 記事を取得する
    #
    # @param url [String] 記事URL
    # @return [Hash] 記事データ
    def fetch_entry(url)
      fetcher = HatenaBlogFetcher.new
      fetcher.fetch_entry(url)
    end

    # 結果を出力する
    #
    # @param entry_data [Hash] 記事データ
    # @param options [Hash] 出力オプション
    # @return [void]
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

    # 生のMarkdown本文を出力する
    #
    # @param entry_data [Hash] 記事データ
    # @return [void]
    def output_raw_content(entry_data)
      puts entry_data[:content]
    end

    # タイトルのみを出力する
    #
    # @param entry_data [Hash] 記事データ
    # @return [void]
    def output_title(entry_data)
      puts entry_data[:title]
    end

    # URLのみを出力する
    #
    # @param entry_data [Hash] 記事データ
    # @return [void]
    def output_url(entry_data)
      puts entry_data[:url]
    end

    # 投稿日時のみを出力する
    #
    # @param entry_data [Hash] 記事データ
    # @return [void]
    def output_date(entry_data)
      puts entry_data[:published]
    end

    # 全情報をフォーマットして出力する
    #
    # @param entry_data [Hash] 記事データ
    # @return [void]
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

    # エラーを処理する
    #
    # @param error [StandardError] 発生したエラー
    # @return [void]
    def handle_error(error)
      warn "エラー: #{error.message}"
      warn error.backtrace
      exit 1
    end
  end
end

# メインエントリーポイント
#
# @return [void]
def main
  HatenaBlogFetcher::CLI.run(ARGV)
end

main if __FILE__ == $PROGRAM_NAME
