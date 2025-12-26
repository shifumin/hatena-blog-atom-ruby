# hatena-blog-atom-ruby

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Ruby scripts for fetching, posting, and updating blog entries on Hatena Blog using the AtomPub API.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Installation](#installation)
- [Usage](#usage)
- [Supported URL Formats](#supported-url-formats)
- [Configuration](#configuration)
- [API Reference](#api-reference)
- [Error Handling](#error-handling)
- [Contributing](#contributing)
- [License](#license)

## Features

### Fetcher
- Fetch individual blog posts by URL
- Support for both date-based URLs and entry ID URLs
- Multiple output formats (full, raw markdown, title only, datetime only, URL only)
- Pagination support for searching entries by date
- Time tolerance matching for date-based URLs (±1 hour)

### Poster
- Post new blog entries from Markdown files
- Draft/publish mode support

### Updater
- Update existing blog entries
- Support for both entry ID and URL (including date-based URLs)
- Draft/publish mode support

### Common
- WSSE authentication for secure API access
- Command-line interface with options
- Secure SSL/TLS connections with certificate validation

## Prerequisites

- Ruby (see `.ruby-version`)
- Bundler
- Hatena Blog API key

## Installation

1. Clone the repository:
```bash
git clone https://github.com/shifumin/hatena-blog-atom-ruby.git
cd hatena-blog-atom-ruby
```

2. Install dependencies:
```bash
bundle install
```

3. Set up environment variables:
```bash
export HATENA_ID='your-hatena-id'
export HATENA_BLOG_ID='your-subdomain.hatenablog.com'
export HATENA_API_KEY='your-api-key-here'
```

### Obtaining Your API Key

1. Log in to your Hatena Blog
2. Go to your blog's dashboard: `https://blog.hatena.ne.jp/{your-hatena-id}/{your-blog-id}/config/detail`
3. Scroll down to "AtomPub" section
4. Click "APIキーを表示" (Show API Key)
5. Copy the displayed API key

Alternatively, you can access the API key settings from:
- Blog Dashboard → Settings (設定) → Advanced Settings (詳細設定) → AtomPub

## Usage

### Fetching Entries

Fetch a blog entry by URL:
```bash
ruby hatena_blog_fetcher.rb https://your-subdomain.hatenablog.com/entry/2024/01/01/123456
```

#### Command-line Options (Fetcher)

- `-r, --raw` - Output raw Markdown content only
- `-t, --title` - Output title only
- `-d, --date` - Output publication datetime only
- `-u, --url` - Output URL only
- `-h, --help` - Display help message

#### Examples (Fetcher)

```bash
# Get full entry information (default)
ruby hatena_blog_fetcher.rb https://your-subdomain.hatenablog.com/entry/2024/01/01/123456

# Get only the raw Markdown content
ruby hatena_blog_fetcher.rb -r https://your-subdomain.hatenablog.com/entry/2024/01/01/123456

# Get only the title
ruby hatena_blog_fetcher.rb -t https://your-subdomain.hatenablog.com/entry/2024/01/01/123456

# Get only the publication datetime
ruby hatena_blog_fetcher.rb -d https://your-subdomain.hatenablog.com/entry/2024/01/01/123456

# Get only the URL
ruby hatena_blog_fetcher.rb -u https://your-subdomain.hatenablog.com/entry/2024/01/01/123456
```

#### Output Examples (Fetcher)

**Full output (default):**
```
============================================================
タイトル: サンプル記事タイトル
投稿日時: 2024-01-01 12:34:56
URL: https://your-subdomain.hatenablog.com/entry/2024/01/01/123456
============================================================
本文（Markdown）:
------------------------------------------------------------
# 見出し

本文のMarkdownコンテンツがここに表示されます。
============================================================
```

**Raw markdown output (`-r`):**
```
# 見出し

本文のMarkdownコンテンツがここに表示されます。
```

**Title only (`-t`):**
```
サンプル記事タイトル
```

### Posting an Entry

Post a new blog entry from a Markdown file:
```bash
ruby hatena_blog_poster.rb -t "Article Title" -f content.md
```

#### Command-line Options (Poster)

- `-t, --title TITLE` - Article title (required)
- `-f, --file FILE` - Markdown file path (required)
- `-p, --publish` - Publish immediately (default: draft)
- `-h, --help` - Display help message

#### Examples (Poster)

```bash
# Post as draft (default)
ruby hatena_blog_poster.rb -t "My New Article" -f article.md

# Publish immediately
ruby hatena_blog_poster.rb -t "My New Article" -f article.md -p
```

### Updating an Entry

Update an existing blog entry:
```bash
ruby hatena_blog_updater.rb -i 13574176438046791234 -t "Updated Title" -f updated_content.md
```

#### Command-line Options (Updater)

- `-u, --url URL` - Entry URL (mutually exclusive with -i)
- `-i, --id ID` - Entry ID (mutually exclusive with -u)
- `-t, --title TITLE` - Article title (required)
- `-f, --file FILE` - Markdown file path (required)
- `-p, --publish` - Publish immediately (default: draft)
- `-h, --help` - Display help message

#### Examples (Updater)

```bash
# Update by entry ID (as draft)
ruby hatena_blog_updater.rb -i 13574176438046791234 -t "Updated Title" -f content.md

# Update by entry URL
ruby hatena_blog_updater.rb -u https://your-subdomain.hatenablog.com/entry/2024/01/01/123456 -t "Updated Title" -f content.md

# Update and publish immediately
ruby hatena_blog_updater.rb -i 13574176438046791234 -t "Updated Title" -f content.md -p
```

## Supported URL Formats

The fetcher supports two types of Hatena Blog URLs:

1. **Date-based URLs**: `https://example.hatenadiary.com/entry/YYYY/MM/DD/HHMMSS`
2. **Entry ID URLs**: `https://example.hatenadiary.com/entry/YYYYMMDD/1234567890`

## Configuration

Configure the scripts using environment variables:

| Variable | Description | Example |
|----------|-------------|---------|
| `HATENA_ID` | Your Hatena ID | `your-hatena-id` |
| `HATENA_BLOG_ID` | Your blog domain | `your-subdomain.hatenablog.com` |
| `HATENA_API_KEY` | Your API key | (see [Obtaining Your API Key](#obtaining-your-api-key)) |

```bash
export HATENA_ID='your-hatena-id'
export HATENA_BLOG_ID='your-subdomain.hatenablog.com'
export HATENA_API_KEY='your-api-key-here'
```

## API Reference

These scripts use the Hatena Blog AtomPub API:
- Endpoint: `https://blog.hatena.ne.jp/{hatena_id}/{blog_id}/atom/entry`
- Authentication: WSSE (X-WSSE header)
- Response format: Atom XML
- Content type: text/x-markdown

### Output Format

The fetcher returns the following data structure:
- `title`: Article title
- `content`: Markdown content (with trailing whitespace removed)
- `published`: Publication datetime in YYYY-MM-DD HH:MM:SS format
- `url`: Article URL

## Error Handling

The scripts provide clear error messages for common issues:
- Missing environment variables: Prompts to set HATENA_ID, HATENA_BLOG_ID, and HATENA_API_KEY
- Invalid URLs: Validates URL format before making API requests
- Network errors: Reports HTTP status codes and error messages
- Entry not found: Clear message when date-based search finds no matching entry
- API authentication failures: Reports 401 errors with guidance

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Write tests for your changes
4. Ensure all tests pass (`rspec`)
5. Check code style (`rubocop`)
6. Commit your changes (`git commit -m 'Add some amazing feature'`)
7. Push to the branch (`git push origin feature/amazing-feature`)
8. Open a Pull Request

## License

This project is open source and available under the [MIT License](LICENSE).