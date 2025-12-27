# hatena-blog-atom-ruby

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Ruby scripts for fetching, posting, and updating blog entries on Hatena Blog using the AtomPub API.

## Features

### Fetcher (`hatena_blog_fetcher.rb`)
- Fetch blog posts by URL (date-based or entry ID format)
- Extract metadata: title, content, categories, draft status, entry ID
- Multiple output formats (full, raw markdown, title, datetime, URL)
- Time tolerance matching for date-based URLs (±1 hour)

### Poster (`hatena_blog_poster.rb`)
- Post new blog entries from Markdown files
- Draft/publish mode support

### Updater (`hatena_blog_updater.rb`)
- Update existing blog entries by ID or URL
- Preserve or modify categories and publication datetime
- Draft/publish mode support

## Prerequisites

- Ruby (see `.ruby-version`)
- Bundler
- Hatena Blog API credentials

## Installation

```bash
git clone https://github.com/shifumin/hatena-blog-atom-ruby.git
cd hatena-blog-atom-ruby
bundle install
```

## Configuration

Set the following environment variables:

```bash
export HATENA_ID='your-hatena-id'
export HATENA_BLOG_ID='your-subdomain.hatenablog.com'
export HATENA_API_KEY='your-api-key'
```

| Variable | Description | Example |
|----------|-------------|---------|
| `HATENA_ID` | Your Hatena ID | `your-hatena-id` |
| `HATENA_BLOG_ID` | Your blog domain | `your-subdomain.hatenablog.com` |
| `HATENA_API_KEY` | API key from blog settings | (see below) |

### Obtaining Your API Key

1. Log in to Hatena Blog
2. Go to: `https://blog.hatena.ne.jp/{HATENA_ID}/{BLOG_ID}/config/detail`
3. Scroll to "AtomPub" section
4. Click "APIキーを表示" (Show API Key)

## Usage

### Fetcher

Fetch a blog entry by URL:

```bash
ruby hatena_blog_fetcher.rb [OPTIONS] URL
```

#### Options

| Option | Description |
|--------|-------------|
| `-r, --raw` | Output raw Markdown content only |
| `-t, --title` | Output title only |
| `-d, --date` | Output publication datetime only |
| `-u, --url` | Output URL only |
| `-h, --help` | Display help message |

#### Supported URL Formats

- Date-based: `https://example.hatenablog.com/entry/2024/01/01/123456`
- Entry ID: `https://example.hatenablog.com/entry/20240101/1234567890`

#### Examples

```bash
# Full entry information
ruby hatena_blog_fetcher.rb https://example.hatenablog.com/entry/2024/01/01/123456

# Raw Markdown only
ruby hatena_blog_fetcher.rb -r https://example.hatenablog.com/entry/2024/01/01/123456

# Title only
ruby hatena_blog_fetcher.rb -t https://example.hatenablog.com/entry/2024/01/01/123456
```

#### Output Example

```
============================================================
タイトル: サンプル記事タイトル
投稿日時: 2024-01-01 12:34:56
URL: https://example.hatenablog.com/entry/2024/01/01/123456
カテゴリ: Ruby, API
下書き: no
エントリーID: 13574176438046791234
============================================================
本文（Markdown）:
------------------------------------------------------------
# 見出し

本文のMarkdownコンテンツ
============================================================
```

### Poster

Post a new blog entry from a Markdown file:

```bash
ruby hatena_blog_poster.rb [OPTIONS]
```

#### Options

| Option | Description |
|--------|-------------|
| `-t, --title TITLE` | Article title (required) |
| `-f, --file FILE` | Markdown file path (required) |
| `-p, --publish` | Publish immediately (default: draft) |
| `-h, --help` | Display help message |

#### Examples

```bash
# Post as draft
ruby hatena_blog_poster.rb -t "My Article" -f article.md

# Publish immediately
ruby hatena_blog_poster.rb -t "My Article" -f article.md -p
```

### Updater

Update an existing blog entry:

```bash
ruby hatena_blog_updater.rb [OPTIONS]
```

#### Options

| Option | Description |
|--------|-------------|
| `-u, --url URL` | Entry URL (mutually exclusive with `-i`) |
| `-i, --id ID` | Entry ID (mutually exclusive with `-u`) |
| `-t, --title TITLE` | Article title (required) |
| `-f, --file FILE` | Markdown file path (required) |
| `-p, --publish` | Publish immediately (default: draft) |
| `-c, --categories CATEGORIES` | Categories (comma-separated) |
| `--updated DATETIME` | Publication datetime (ISO8601 format) |
| `-h, --help` | Display help message |

#### Examples

```bash
# Update by entry ID
ruby hatena_blog_updater.rb -i 13574176438046791234 -t "Updated Title" -f content.md

# Update by URL
ruby hatena_blog_updater.rb -u https://example.hatenablog.com/entry/2024/01/01/123456 \
  -t "Updated Title" -f content.md

# Update and publish with categories
ruby hatena_blog_updater.rb -i 13574176438046791234 -t "Updated Title" -f content.md \
  -p -c "Ruby,API"

# Preserve publication datetime
ruby hatena_blog_updater.rb -i 13574176438046791234 -t "Updated Title" -f content.md \
  --updated "2024-01-01T12:34:56+09:00"
```

## API Reference

[Hatena Blog AtomPub API](https://developer.hatena.ne.jp/ja/documents/blog/apis/atom)

## License

[MIT License](LICENSE)
