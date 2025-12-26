# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby scripts for fetching, posting, and updating blog entries on Hatena Blog using the AtomPub API. The project consists of three main scripts:

- `hatena_blog_fetcher.rb` - Fetch blog entries by URL
- `hatena_blog_poster.rb` - Post new blog entries
- `hatena_blog_updater.rb` - Update existing blog entries

## Development Commands

### Dependencies
```bash
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
rspec spec/hatena_blog_fetcher_spec.rb
```

### Running the Scripts

#### Fetcher (fetch blog entries)
```bash
./hatena_blog_fetcher.rb [URL]
./hatena_blog_fetcher.rb -r [URL]  # Raw Markdown content only
./hatena_blog_fetcher.rb -t [URL]  # Title only
./hatena_blog_fetcher.rb -d [URL]  # Date/time only
./hatena_blog_fetcher.rb -u [URL]  # URL only
```

#### Poster (create new entries)
```bash
ruby hatena_blog_poster.rb -t "Title" -f content.md      # Post as draft
ruby hatena_blog_poster.rb -t "Title" -f content.md -p   # Publish immediately
```

#### Updater (update existing entries)
```bash
ruby hatena_blog_updater.rb -i ENTRY_ID -t "Title" -f content.md      # Update by ID (draft)
ruby hatena_blog_updater.rb -u URL -t "Title" -f content.md           # Update by URL
ruby hatena_blog_updater.rb -i ENTRY_ID -t "Title" -f content.md -p   # Update and publish
```

## Environment Setup

### Required Environment Variables
- `HATENA_ID`: Your Hatena ID
- `HATENA_BLOG_ID`: Your blog domain (e.g., `your-subdomain.hatenablog.com`)
- `HATENA_API_KEY`: Your Hatena Blog API key

```bash
export HATENA_ID='your-hatena-id'
export HATENA_BLOG_ID='your-subdomain.hatenablog.com'
export HATENA_API_KEY='your-api-key-here'
```

### Ruby Version
- See `.ruby-version`

## Architecture & Code Structure

### Authentication
All scripts use WSSE authentication for the Hatena Blog AtomPub API:
- WSSE header creation with SHA1 digest (`create_wsse_header` method)
- Nonce generation using SecureRandom
- Digest calculation: SHA1(nonce + created + api_key)

### SSL/TLS Configuration
Custom SSL certificate verification for secure API connections:
- Certificate validation: Enabled (VERIFY_PEER mode)
- CRL checking: Disabled (to avoid "unable to get certificate CRL" errors)
- Implementation in `create_cert_store` method

### URL Handling
Supported URL formats:
1. Date-based URLs: `/entry/YYYY/MM/DD/HHMMSS`
2. Entry ID URLs: `/entry/YYYYMMDD/1234567890`

For date-based URLs, scripts search through the entry list to find matching articles by comparing timestamps.

### Key Components

#### HatenaBlogFetcher class
Fetches blog entries from the API:
- `fetch_entry(url)`: Fetches a single entry by URL
- `find_entry_by_date(date, time)`: Searches entries by date/time with pagination

#### HatenaBlogPoster class
Posts new blog entries:
- `post_entry(title:, content:, draft:)`: Creates a new entry

#### HatenaBlogUpdater class
Updates existing blog entries:
- `update_entry(entry_url_or_id:, title:, content:, draft:)`: Updates an existing entry
- Supports entry ID, entry URL, and date-based URL formats

#### CLI classes
Each script has an inner `CLI` class handling command-line interaction:
- `HatenaBlogFetcher::CLI`
- `HatenaBlogPoster::CLI`
- `HatenaBlogUpdater::CLI`

### API Details
- Endpoint: `https://blog.hatena.ne.jp/{HATENA_ID}/{BLOG_ID}/atom/entry`
- Authentication: WSSE (X-WSSE header)
- Request/Response format: Atom XML
- Content type: text/x-markdown

## Development Notes

### Testing
- RSpec for unit tests
- WebMock for HTTP request mocking
- Coverage includes normal cases, edge cases, and error handling

### Test Files
- `spec/hatena_blog_fetcher_spec.rb` / `spec/hatena_blog_fetcher/cli_spec.rb`
- `spec/hatena_blog_poster_spec.rb` / `spec/hatena_blog_poster/cli_spec.rb`
- `spec/hatena_blog_updater_spec.rb` / `spec/hatena_blog_updater/cli_spec.rb`

### Code Style
- Uses frozen string literals
- Follows Ruby community conventions
- RuboCop and RuboCop-RSpec configured (see `.rubocop.yml`)
