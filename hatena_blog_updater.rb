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

# はてなブログAtomPub APIを使用してブログ記事を更新するクラス
#
# @example 基本的な使用方法
#   updater = HatenaBlogUpdater.new
#   result = updater.update_entry(
#     entry_url_or_id: "13574176438046791234",
#     title: "Updated Title",
#     content: "# Updated Content",
#     draft: false
#   )
#   puts result[:url]
#
# @see https://developer.hatena.ne.jp/ja/documents/blog/apis/atom
class HatenaBlogUpdater
  # @return [String] はてなID
  HATENA_ID = "shifumin"
  # @return [String] ブログID（ドメイン）
  BLOG_ID = "shifumin.hatenadiary.com"
  # @return [String] AtomPub APIエンドポイント
  API_ENDPOINT = "https://blog.hatena.ne.jp/#{HATENA_ID}/#{BLOG_ID}/atom/entry".freeze

  # HatenaBlogUpdaterの新しいインスタンスを作成する
  #
  # @raise [ArgumentError] 環境変数HATENA_API_KEYが設定されていない場合
  def initialize
    @api_key = ENV.fetch("HATENA_API_KEY", nil)
    validate_api_key!
  end

  # 記事を更新する
  #
  # @param entry_url_or_id [String] 記事URLまたはエントリーID
  # @param title [String] 新しいタイトル
  # @param content [String] 新しい本文（Markdown）
  # @param draft [Boolean] 下書き状態にするか（デフォルト: false）
  # @return [Hash] 更新結果
  # @option return [String] :title 記事タイトル
  # @option return [String] :url 記事URL
  # @option return [String] :edit_url 編集画面URL
  # @option return [String] :published 投稿日時
  # @raise [RuntimeError] 記事が見つからない場合
  # @raise [RuntimeError] APIリクエストが失敗した場合
  def update_entry(entry_url_or_id:, title:, content:, draft: false)
    entry_id = resolve_entry_id(entry_url_or_id)
    entry_api_url = "#{API_ENDPOINT}/#{entry_id}"

    xml_body = build_entry_xml(title, content, draft)
    response = put_with_wsse_auth(entry_api_url, xml_body)
    parse_response(response.body)
  end

  private

  # APIキーの存在を検証する
  #
  # @raise [ArgumentError] APIキーが未設定または空の場合
  def validate_api_key!
    return unless @api_key.nil? || @api_key.empty?

    raise ArgumentError, "環境変数 HATENA_API_KEY が設定されていません。\n" \
                         "export HATENA_API_KEY='あなたのAPIキー' を実行してください。"
  end

  # URLまたはIDからエントリーIDを解決する
  #
  # @param entry_url_or_id [String] 記事URLまたはエントリーID
  # @return [String] エントリーID
  # @raise [RuntimeError] 日付ベースURLの記事が見つからない場合
  def resolve_entry_id(entry_url_or_id)
    # 純粋な数字のみの場合はエントリーIDとして扱う
    return entry_url_or_id if entry_url_or_id.match?(/\A\d+\z/)

    # URL形式の場合
    if date_based_url?(entry_url_or_id)
      find_entry_id_by_date_url(entry_url_or_id)
    else
      extract_entry_id(entry_url_or_id)
    end
  end

  # URLが日付ベース形式かどうかを判定する
  #
  # @param url [String] 判定対象のURL
  # @return [Boolean] 日付ベース形式の場合true
  def date_based_url?(url)
    url.match?(%r{/entry/(\d{4})/(\d{2})/(\d{2})/(\d+)})
  end

  # URLからエントリーIDを抽出する
  #
  # @param url [String] 記事URL
  # @return [String] エントリーID
  # @raise [ArgumentError] 無効なURL形式の場合
  def extract_entry_id(url)
    uri = URI.parse(url)
    path_parts = uri.path.split("/")

    entry_index = path_parts.index("entry")
    raise ArgumentError, "無効なURLです: #{url}" unless entry_index

    path_parts[(entry_index + 1)..].join("/")
  end

  # 日付ベースURLからエントリーIDを取得する
  #
  # @param url [String] 日付ベース形式の記事URL
  # @return [String] エントリーID
  # @raise [RuntimeError] 記事が見つからない場合
  def find_entry_id_by_date_url(url)
    date_match = url.match(%r{/entry/(\d{4})/(\d{2})/(\d{2})/(\d+)})
    year, month, day, time = date_match[1..4]
    target_date = "#{year}-#{month}-#{day}"

    entry_id = search_entry_in_pages(target_date, time)
    raise "指定された日付の記事が見つかりませんでした: #{url}" unless entry_id

    entry_id
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

      page_candidates = find_matching_entries_in_page(doc, target_date, time_part)
      candidates.concat(page_candidates)

      perfect_match = candidates.find { |c| c[:score].zero? }
      return perfect_match[:entry_id] if perfect_match

      next_url = get_next_page_url(doc)
    end

    return nil if candidates.empty?

    best_candidate = candidates.min_by { |c| c[:score] }
    best_candidate[:entry_id]
  end

  # 1ページ内で一致する記事を検索する
  #
  # @param doc [REXML::Document] XMLドキュメント
  # @param target_date [String] 検索対象の日付（YYYY-MM-DD形式）
  # @param time_part [String] 検索対象の時刻（HHMMSS形式）
  # @return [Array<Hash>] 候補記事の配列
  def find_matching_entries_in_page(doc, target_date, time_part)
    candidates = []
    doc.elements.each("feed/entry") do |entry|
      score = calculate_entry_match_score(entry, target_date, time_part)
      next if score.nil?

      entry_id = extract_entry_id_from_element(entry)
      next unless entry_id

      candidates << { entry_id: entry_id, score: score }
    end
    candidates
  end

  # 記事のマッチスコアを計算する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @param target_date [String] 検索対象の日付（YYYY-MM-DD形式）
  # @param time_part [String] 検索対象の時刻（HHMMSS形式）
  # @return [Integer, nil] マッチスコア、候補外の場合はnil
  def calculate_entry_match_score(entry, target_date, time_part)
    published = entry.elements["published"]&.text
    return nil unless published

    published_datetime = parse_published_datetime(published)

    entry_url = extract_url_from_entry_element(entry)
    return 0 if entry_url&.include?("/entry/#{target_date.tr('-', '/')}/#{time_part}")

    date_diff = calculate_date_diff(published_datetime[:date], target_date)
    return nil if date_diff > 7

    time_diff = calculate_time_diff(published_datetime[:time], time_part)
    return nil if time_diff > 3600

    (date_diff * 86_400) + time_diff
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
    link = entry.elements['link[@rel="alternate"]']
    return link.attributes["href"] if link&.attributes&.[]("href")

    id_element = entry.elements["id"]
    return nil unless id_element&.text

    entry_id = id_element.text.split("-").last
    "https://#{BLOG_ID}/entry/#{entry_id}"
  end

  # 次ページのURLを取得する
  #
  # @param doc [REXML::Document] XMLドキュメント
  # @return [String, nil] 次ページのURL、存在しない場合はnil
  def get_next_page_url(doc)
    next_link = doc.elements['feed/link[@rel="next"]']
    next_link&.attributes&.[]("href")
  end

  # Atom XML形式のエントリを構築する
  #
  # @param title [String] 記事タイトル
  # @param content [String] 記事本文（Markdown）
  # @param draft [Boolean] 下書き状態にするか
  # @return [String] XML文字列
  def build_entry_xml(title, content, draft)
    doc = REXML::Document.new
    doc << REXML::XMLDecl.new("1.0", "utf-8")

    entry = doc.add_element("entry")
    entry.add_namespace("http://www.w3.org/2005/Atom")
    entry.add_namespace("app", "http://www.w3.org/2007/app")

    entry.add_element("title").add_text(title)

    author = entry.add_element("author")
    author.add_element("name").add_text(HATENA_ID)

    content_element = entry.add_element("content")
    content_element.add_attribute("type", "text/x-markdown")
    content_element.add_text(content)

    entry.add_element("updated").add_text(Time.now.utc.iso8601)

    control = entry.add_element("app:control")
    control.add_element("app:draft").add_text(draft ? "yes" : "no")

    output = +""
    doc.write(output)
    output
  end

  # WSSE認証ヘッダーを生成する
  #
  # @return [String] X-WSSEヘッダー値
  def create_wsse_header
    nonce = SecureRandom.random_bytes(20)
    created = Time.now.utc.iso8601

    digest_input = String.new(encoding: Encoding::BINARY)
    digest_input << nonce
    digest_input << created
    digest_input << @api_key

    password_digest = Base64.strict_encode64(
      Digest::SHA1.digest(digest_input)
    )

    nonce_base64 = Base64.strict_encode64(nonce)

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

  # WSSE認証付きでHTTP PUTリクエストを実行する
  #
  # @param url [String] リクエスト先URL
  # @param body [String] リクエストボディ
  # @return [Net::HTTPResponse] HTTPレスポンス
  # @raise [RuntimeError] APIリクエストが失敗した場合
  def put_with_wsse_auth(url, body)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = create_cert_store

    request = Net::HTTP::Put.new(uri.request_uri)
    request["X-WSSE"] = create_wsse_header
    request["Content-Type"] = "application/atom+xml"
    request["Accept"] = "application/atom+xml"
    request.body = body

    response = http.request(request)

    unless response.is_a?(Net::HTTPSuccess)
      body_text = response.body.to_s.dup.force_encoding("UTF-8")
      raise "APIリクエストが失敗しました: #{response.code} #{response.message}\n#{body_text}"
    end

    response
  end

  # SSL証明書ストアを作成する
  #
  # @return [OpenSSL::X509::Store] 証明書ストア
  def create_cert_store
    store = OpenSSL::X509::Store.new
    store.set_default_paths
    store
  end

  # レスポンスXMLをパースして結果を抽出する
  #
  # @param xml_body [String] XMLレスポンス本文
  # @return [Hash] 更新結果
  def parse_response(xml_body)
    doc = REXML::Document.new(xml_body)
    entry = doc.root
    entry_id = extract_response_entry_id(entry)

    {
      title: entry.elements["title"]&.text,
      url: extract_url_from_entry(entry),
      edit_url: build_edit_url(entry_id),
      published: entry.elements["published"]&.text
    }
  end

  # レスポンスからエントリーIDを抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String, nil] エントリーID
  def extract_response_entry_id(entry)
    id_text = entry.elements["id"]&.text
    return nil unless id_text

    id_text.split("-").last
  end

  # 編集画面URLを構築する
  #
  # @param entry_id [String] エントリーID
  # @return [String, nil] 編集画面URL
  def build_edit_url(entry_id)
    return nil unless entry_id

    "https://blog.hatena.ne.jp/#{HATENA_ID}/#{BLOG_ID}/edit?entry=#{entry_id}"
  end

  # エントリからURLを抽出する
  #
  # @param entry [REXML::Element] 記事のXML要素
  # @return [String, nil] 記事URL
  def extract_url_from_entry(entry)
    alternate_link = entry.elements['link[@rel="alternate"]']
    alternate_link&.attributes&.[]("href")
  end
end

class HatenaBlogUpdater
  # コマンドラインインターフェースを提供するクラス
  #
  # @example 基本的な使用方法
  #   HatenaBlogUpdater::CLI.run(ARGV)
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
      validate_options!(options)

      content = read_content_file(options[:file])
      draft = !options[:publish]
      entry_url_or_id = options[:url] || options[:id]

      result = update_entry(entry_url_or_id, options[:title], content, draft)
      output_result(result, draft)
    rescue StandardError => e
      handle_error(e)
    end

    private

    # コマンドラインオプションをパースする
    #
    # @param args [Array<String>] コマンドライン引数
    # @return [Hash] パースされたオプション
    def parse_options(args)
      options = { publish: false }
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
        opts.banner = "使用方法: ruby #{$PROGRAM_NAME} [オプション]"
        opts.separator ""
        opts.separator "はてなブログの記事を更新します"
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

      opts.on("-u", "--url URL", "記事URL（-iと排他）") do |url|
        options[:url] = url
      end

      opts.on("-i", "--id ID", "エントリーID（-uと排他）") do |id|
        options[:id] = id
      end

      opts.on("-t", "--title TITLE", "記事タイトル（必須）") do |title|
        options[:title] = title
      end

      opts.on("-f", "--file FILE", "Markdownファイルパス（必須）") do |file|
        options[:file] = file
      end

      opts.on("-p", "--publish", "公開する（デフォルトは下書き）") do
        options[:publish] = true
      end
    end

    # オプションを検証する
    #
    # @param options [Hash] パースされたオプション
    # @raise [ArgumentError] 必須オプションが不足している場合
    def validate_options!(options)
      errors = []

      if options[:url] && options[:id]
        errors << "URLとIDは同時に指定できません（-u または -i のいずれか）"
      elsif !options[:url] && !options[:id]
        errors << "URLまたはID（-u または -i）は必須です"
      end

      errors << "タイトル（-t）は必須です" unless options[:title]
      errors << "ファイル（-f）は必須です" unless options[:file]

      return if errors.empty?

      raise ArgumentError, errors.join("\n")
    end

    # ファイルから本文を読み込む
    #
    # @param file_path [String] ファイルパス
    # @return [String] ファイル内容
    # @raise [ArgumentError] ファイルが存在しない場合
    def read_content_file(file_path)
      raise ArgumentError, "ファイルが見つかりません: #{file_path}" unless File.exist?(file_path)

      File.read(file_path)
    end

    # 記事を更新する
    #
    # @param entry_url_or_id [String] 記事URLまたはエントリーID
    # @param title [String] タイトル
    # @param content [String] 本文
    # @param draft [Boolean] 下書き状態にするか
    # @return [Hash] 更新結果
    def update_entry(entry_url_or_id, title, content, draft)
      updater = HatenaBlogUpdater.new
      updater.update_entry(entry_url_or_id: entry_url_or_id, title: title, content: content, draft: draft)
    end

    # 結果を出力する
    #
    # @param result [Hash] 更新結果
    # @param draft [Boolean] 下書き状態か
    # @return [void]
    def output_result(result, draft)
      status = draft ? "下書き" : "公開"
      puts "更新が完了しました（#{status}）"
      puts "タイトル: #{result[:title]}"
      url = draft ? result[:edit_url] : result[:url]
      puts "URL: #{url}"
    end

    # エラーを処理する
    #
    # @param error [StandardError] 発生したエラー
    # @return [void]
    def handle_error(error)
      warn "エラー: #{error.message}"
      exit 1
    end
  end
end

# メインエントリーポイント
#
# @return [void]
def main
  HatenaBlogUpdater::CLI.run(ARGV)
end

main if __FILE__ == $PROGRAM_NAME
