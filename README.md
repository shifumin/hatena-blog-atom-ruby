# hatena-blog-atom-ruby

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A Ruby script for fetching blog entries from Hatena Blog using the AtomPub API.

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

- Fetch individual blog posts by URL
- Support for both date-based URLs and entry ID URLs
- Multiple output formats (full, raw markdown, title only, datetime only, URL only)
- WSSE authentication for secure API access
- Command-line interface with options
- Automatic removal of trailing whitespace from content
- Pagination support for searching entries by date
- Time tolerance matching for date-based URLs (±1 hour)
- Secure SSL/TLS connections with certificate validation

## Prerequisites

- Ruby (see `.ruby-version`)
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

3. Set up your Hatena Blog API key:
```bash
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

### Basic Usage

Fetch a blog entry by URL:
```bash
./hatena_blog_fetcher.rb https://shifumin.hatenadiary.com/entry/2024/01/01/123456
```

### Command-line Options

- `-r, --raw` - Output raw Markdown content only
- `-t, --title` - Output title only
- `-d, --date` - Output publication datetime only
- `-u, --url` - Output URL only
- `-h, --help` - Display help message

### Examples

```bash
# Get full entry information (default)
./hatena_blog_fetcher.rb https://shifumin.hatenadiary.com/entry/2024/01/01/123456

# Get only the raw Markdown content
./hatena_blog_fetcher.rb -r https://shifumin.hatenadiary.com/entry/2024/01/01/123456

# Get only the title
./hatena_blog_fetcher.rb -t https://shifumin.hatenadiary.com/entry/2024/01/01/123456

# Get only the publication datetime
./hatena_blog_fetcher.rb -d https://shifumin.hatenadiary.com/entry/2024/01/01/123456

# Get only the URL
./hatena_blog_fetcher.rb -u https://shifumin.hatenadiary.com/entry/2024/01/01/123456
```

### Output Examples

**Full output (default):**
```
============================================================
タイトル: サンプル記事タイトル
投稿日時: 2024-01-01 12:34:56
URL: https://shifumin.hatenadiary.com/entry/2024/01/01/123456
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

## Supported URL Formats

The script supports two types of Hatena Blog URLs:

1. **Date-based URLs**: `https://example.hatenadiary.com/entry/YYYY/MM/DD/HHMMSS`
2. **Entry ID URLs**: `https://example.hatenadiary.com/entry/YYYYMMDD/1234567890`

## Configuration

The script is configured for the blog `shifumin.hatenadiary.com`. To use with a different blog, modify the following constants in `hatena_blog_fetcher.rb`:

```ruby
HATENA_ID = 'your-hatena-id'
BLOG_ID = 'your-blog.hatenadiary.com'
```

## API Reference

This script uses the Hatena Blog AtomPub API:
- Endpoint: `https://blog.hatena.ne.jp/{hatena_id}/{blog_id}/atom/entry`
- Authentication: WSSE (X-WSSE header)
- Response format: Atom XML
- Content type: text/x-markdown

### Output Format

The script returns the following data structure:
- `title`: Article title
- `content`: Markdown content (with trailing whitespace removed)
- `published`: Publication datetime in YYYY-MM-DD HH:MM:SS format
- `url`: Article URL

## Error Handling

The script provides clear error messages for common issues:
- Missing API key: Prompts to set HATENA_API_KEY environment variable
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