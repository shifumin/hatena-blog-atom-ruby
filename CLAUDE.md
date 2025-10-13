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
- Ruby 3.4.7 (managed via `.ruby-version`)

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
- `fetch_entry`: Fetches a single entry by URL (routes to appropriate method based on URL type)
- `find_entry_by_date`: Searches entries by date/time for date-based URLs with pagination support
- Private helper methods following Single Responsibility Principle:
  - `date_based_url?`: Checks if URL is date-based format
  - `fetch_entry_by_date`: Handles date-based URL fetching
  - `fetch_entry_by_id`: Handles standard entry ID fetching
  - `search_entry_in_pages`: Manages pagination when searching entries
  - `parse_entry`: Parses XML response (delegates to specific extraction methods)
  - `extract_title_from_entry`: Extracts title from XML entry
  - `extract_content_from_entry`: Extracts and strips trailing whitespace from content
  - `extract_published_date_from_entry`: Extracts published datetime
  - `extract_url_from_entry`: Extracts URL from alternate link or constructs from ID
  - `create_wsse_header`: Generates WSSE authentication header
  - `get_with_wsse_auth`: Makes authenticated HTTP requests with SSL certificate validation
  - `create_cert_store`: Creates OpenSSL certificate store with CRL checking disabled

#### CommandLineInterface class
Handles CLI interaction and output formatting:
- `run`: Main entry point for CLI execution
- `parse_options`: Processes command-line arguments
- `output_result`: Routes to appropriate output format
- Separate methods for each output format (raw, title, date, url, full)

### API Details
- Endpoint: `https://blog.hatena.ne.jp/{HATENA_ID}/{BLOG_ID}/atom/entry`
- Authentication: WSSE (X-WSSE header)
- Response format: Atom XML
- Content type: text/x-markdown

## Development Notes

### Recent Improvements
- **Ruby version upgrade** (2025-10-13):
  - Upgraded from Ruby 3.4.5 to 3.4.7
  - Ensures latest security patches and improvements
- **SSL certificate verification fix** (2025-10-13):
  - Fixed "unable to get certificate CRL" error
  - Implemented custom cert_store with CRL checking disabled
  - Maintained core security features (hostname, expiration, trust chain validation)
- Added URL output option (`-u, --url`)
- Changed output label from "投稿日" to "投稿日時" for clarity
- Refactored `parse_entry` method to follow Single Responsibility Principle
- Enhanced test coverage for XML field missing scenarios
- Added test for API errors during pagination
- Fixed issue with trailing blank lines in content output
- Separated CLI logic into dedicated CommandLineInterface class
- Fixed time matching for date-based URLs:
  - Corrected HHMMSS to seconds conversion in `time_matches?` method
  - Increased time tolerance from 30 minutes to 1 hour (3600 seconds) for better flexibility
  - This allows matching articles posted within 1 hour of the specified time in the URL
- Implemented apparent datetime for date-based URLs:
  - Date-based URLs now display the apparent datetime from the URL instead of the actual published time
  - Example: `/entry/2020/03/21/230000` displays as "2020-03-21 23:00:00" regardless of actual publication time
  - This makes the output consistent with the URL structure and user expectations
- Enhanced date-based entry matching algorithm:
  - Added time tolerance check in `calculate_entry_match_score` method
  - Entries with time differences exceeding 1 hour (3600 seconds) are now excluded from candidates
  - This prevents incorrect matches when multiple articles exist on the same date

### Testing Coverage
The project has comprehensive test coverage with RSpec:
- **HatenaBlogFetcher class**: 23 test cases covering all public methods
  - Normal cases: Standard URL formats, date-based searches
  - Edge cases: Missing XML fields, time tolerance boundaries
  - Error cases: 401/404/500 errors, invalid URLs, API failures
- **CommandLineInterface class**: 9 test cases for all CLI options
- WebMock used for mocking HTTP requests
- Private methods tested through public interface
- Total: 32 test examples, 100% passing

### Code Style
- Uses frozen string literals
- Follows Ruby community conventions
- RuboCop and RuboCop-RSpec configured with pragmatic limits:
  - MethodLength: Max 30 (default: 10)
  - AbcSize: Max 30 (default: 17)
  - ClassLength: Disabled (default: 100)
  - RSpec/ExampleLength: Max 6 (default: 5)
- All methods follow Single Responsibility Principle
- No RuboCop violations with current configuration

### Known Issues Resolved
- **SSL certificate CRL verification error**: Fixed by implementing custom cert_store that disables CRL checking while maintaining core certificate validation
- **Content trailing whitespace**: Fixed by adding `rstrip` to parsed content
- **Time matching tolerance**: Corrected time conversion and increased tolerance to 1 hour for date-based URL matching