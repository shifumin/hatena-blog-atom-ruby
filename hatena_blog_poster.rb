# frozen_string_literal: true

require "net/http"
require "uri"
require "rexml/document"
require "digest/sha1"
require "base64"
require "securerandom"
require "time"
require "optparse"
require "openssl"

# はてなブログAtomPub APIを使用してブログ記事を投稿するクラス
class HatenaBlogPoster
  HATENA_ID = "shifumin"
  BLOG_ID = "shifumin.hatenadiary.com"
  API_ENDPOINT = "https://blog.hatena.ne.jp/#{HATENA_ID}/#{BLOG_ID}/atom/entry".freeze

  def initialize
    @api_key = ENV.fetch("HATENA_API_KEY", nil)
    validate_api_key!
  end

  # 記事を投稿する
  #
  # @param title [String] 記事タイトル
  # @param content [String] 記事本文（Markdown）
  # @param draft [Boolean] 下書きとして保存するか
  # @return [Hash] 投稿結果
  def post_entry(title:, content:, draft: false)
    xml_body = build_entry_xml(title, content, draft)
    response = post_with_wsse_auth(API_ENDPOINT, xml_body)
    parse_response(response.body)
  end

  private

  def validate_api_key!
    return unless @api_key.nil? || @api_key.empty?

    raise ArgumentError, "環境変数 HATENA_API_KEY が設定されていません。\n" \
                         "export HATENA_API_KEY='あなたのAPIキー' を実行してください。"
  end

  # Atom XML形式のエントリを構築する
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

  # WSSE認証付きでHTTP POSTリクエストを実行する
  def post_with_wsse_auth(url, body)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.verify_mode = OpenSSL::SSL::VERIFY_PEER
    http.cert_store = create_cert_store

    request = Net::HTTP::Post.new(uri.request_uri)
    request["X-WSSE"] = create_wsse_header
    request["Content-Type"] = "application/atom+xml"
    request["Accept"] = "application/atom+xml"
    request.body = body

    response = http.request(request)

    unless response.is_a?(Net::HTTPCreated)
      body_text = response.body.to_s.dup.force_encoding("UTF-8")
      raise "APIリクエストが失敗しました: #{response.code} #{response.message}\n#{body_text}"
    end

    response
  end

  # SSL証明書ストアを作成する
  def create_cert_store
    store = OpenSSL::X509::Store.new
    store.set_default_paths
    store
  end

  # レスポンスXMLをパースして結果を抽出する
  def parse_response(xml_body)
    doc = REXML::Document.new(xml_body)
    entry = doc.root

    {
      title: entry.elements["title"]&.text,
      url: extract_url_from_entry(entry),
      published: entry.elements["published"]&.text
    }
  end

  # エントリからURLを抽出する
  def extract_url_from_entry(entry)
    alternate_link = entry.elements['link[@rel="alternate"]']
    alternate_link&.attributes&.[]("href")
  end
end

# コマンドラインインターフェースを提供するクラス
class CommandLineInterface
  def self.run(args)
    new.run(args)
  end

  def run(args)
    options = parse_options(args)
    validate_options!(options)

    content = read_content_file(options[:file])
    draft = !options[:publish]
    result = post_entry(options[:title], content, draft)
    output_result(result, draft)
  rescue StandardError => e
    handle_error(e)
  end

  private

  def parse_options(args)
    options = { publish: false }
    parser = create_option_parser(options)
    parser.parse!(args)
    options
  end

  def create_option_parser(options)
    OptionParser.new do |opts|
      opts.banner = "使用方法: ruby #{$PROGRAM_NAME} [オプション]"
      opts.separator ""
      opts.separator "はてなブログに記事を投稿します"
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

  def validate_options!(options)
    errors = []
    errors << "タイトル（-t）は必須です" unless options[:title]
    errors << "ファイル（-f）は必須です" unless options[:file]

    return if errors.empty?

    raise ArgumentError, errors.join("\n")
  end

  def read_content_file(file_path)
    raise ArgumentError, "ファイルが見つかりません: #{file_path}" unless File.exist?(file_path)

    File.read(file_path)
  end

  def post_entry(title, content, draft)
    poster = HatenaBlogPoster.new
    poster.post_entry(title: title, content: content, draft: draft)
  end

  def output_result(result, draft)
    status = draft ? "下書き" : "公開"
    puts "投稿が完了しました（#{status}）"
    puts "タイトル: #{result[:title]}"
    puts "URL: #{result[:url]}"
  end

  def handle_error(error)
    warn "エラー: #{error.message}"
    exit 1
  end
end

def main
  CommandLineInterface.run(ARGV)
end

main if __FILE__ == $PROGRAM_NAME
