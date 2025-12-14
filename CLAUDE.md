# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Ruby script for fetching blog entries from Hatena Blog using the AtomPub API. The main script `hatena_blog_fetcher.rb` provides a command-line interface to retrieve blog posts by URL.

## Development Commands

### Dependencies
```bash
# Install dependencies
bundle install
```

### Testing & Linting
```bash
# Run RuboCop linter
rubocop

# Auto-fix linting issues
rubocop -a

# Run RSpec tests
rspec
# Run specific test file
rspec spec/path/to/spec_file.rb
# Run specific test line
rspec spec/path/to/spec_file.rb:42
```

### Running the Script
```bash
# Basic usage
./hatena_blog_fetcher.rb [URL]

# Output options
./hatena_blog_fetcher.rb -r [URL]  # Raw Markdown content only
./hatena_blog_fetcher.rb -t [URL]  # Title only
./hatena_blog_fetcher.rb -d [URL]  # Date/time only
./hatena_blog_fetcher.rb -u [URL]  # URL only
```

## Environment Setup

### Required Environment Variables
- `HATENA_API_KEY`: Your Hatena Blog API key (required for authentication)
  ```bash
  export HATENA_API_KEY='your-api-key-here'
  ```

### Ruby Version
- See `.ruby-version`

## Architecture & Code Structure

### Authentication
The codebase uses WSSE authentication for the Hatena Blog AtomPub API:
- WSSE header creation with SHA1 digest (`create_wsse_header` method)
- Nonce generation using SecureRandom
- Digest calculation: SHA1(nonce + created + api_key)

### SSL/TLS Configuration
The script uses custom SSL certificate verification to ensure secure API connections:
- **Certificate validation**: Enabled (VERIFY_PEER mode)
- **CRL checking**: Disabled (to avoid "unable to get certificate CRL" errors)
- **Security features maintained**:
  - Hostname verification
  - Certificate expiration checking
  - Trust chain validation
- Implementation in `create_cert_store` method using OpenSSL::X509::Store

### URL Handling
The fetcher supports two URL formats:
1. Date-based URLs: `/entry/YYYY/MM/DD/HHMMSS`
2. Entry ID URLs: Standard entry IDs

For date-based URLs, the script searches through the entry list to find matching articles by comparing timestamps.

### Key Components

#### HatenaBlogFetcher class
Main class handling API interactions:
- `fetch_entry(url)`: Fetches a single entry by URL
- `find_entry_by_date(date, time)`: Searches entries by date/time with pagination

#### CommandLineInterface class
Handles CLI interaction and output formatting:
- `run(args)`: Main entry point for CLI execution

### API Details
- Endpoint: `https://blog.hatena.ne.jp/{HATENA_ID}/{BLOG_ID}/atom/entry`
- Authentication: WSSE (X-WSSE header)
- Response format: Atom XML
- Content type: text/x-markdown

## Development Notes

### Testing
- RSpec for unit tests
- WebMock for HTTP request mocking
- Coverage includes normal cases, edge cases, and error handling

### Code Style
- Uses frozen string literals
- Follows Ruby community conventions
- RuboCop and RuboCop-RSpec configured (see `.rubocop.yml`)