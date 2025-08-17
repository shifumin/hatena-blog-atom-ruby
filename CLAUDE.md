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
./hatena_blog_fetcher.rb -d [URL]  # Date only
```

## Environment Setup

### Required Environment Variables
- `HATENA_API_KEY`: Your Hatena Blog API key (required for authentication)
  ```bash
  export HATENA_API_KEY='your-api-key-here'
  ```

### Ruby Version
- Ruby 3.4.5 (managed via `.ruby-version`)

## Architecture & Code Structure

### Authentication
The codebase uses WSSE authentication for the Hatena Blog AtomPub API:
- WSSE header creation with SHA1 digest (`create_wsse_header` method)
- Nonce generation using SecureRandom
- Digest calculation: SHA1(nonce + created + api_key)

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
  - `parse_entry`: Parses XML response and strips trailing whitespace from content
  - `create_wsse_header`: Generates WSSE authentication header
  - `get_with_wsse_auth`: Makes authenticated HTTP requests

#### CommandLineInterface class
Handles CLI interaction and output formatting:
- `run`: Main entry point for CLI execution
- `parse_options`: Processes command-line arguments
- `output_result`: Routes to appropriate output format
- Separate methods for each output format (raw, title, date, full)

### API Details
- Endpoint: `https://blog.hatena.ne.jp/{HATENA_ID}/{BLOG_ID}/atom/entry`
- Authentication: WSSE (X-WSSE header)
- Response format: Atom XML
- Content type: text/x-markdown

## Development Notes

### Recent Improvements
- Refactored code to follow Single Responsibility Principle
- Fixed issue with trailing blank lines in content output
- Removed unnecessary test script (test_list.rb)
- Added comprehensive test coverage for all public methods
- Separated CLI logic into dedicated CommandLineInterface class
- Removed debug logging code that was hardcoded for specific dates

### Testing Coverage
The project has comprehensive test coverage with RSpec:
- Tests for HatenaBlogFetcher class (all public methods)
- Tests for CommandLineInterface class
- WebMock used for mocking HTTP requests
- Tests cover normal cases, edge cases, and error handling
- Private methods are not directly tested (tested through public interface)

### Code Style
- Uses frozen string literals
- Follows Ruby community conventions
- RuboCop and RuboCop-RSpec configured for style enforcement
- Methods follow Single Responsibility Principle

### Known Issues Resolved
- Content trailing whitespace: Fixed by adding `rstrip` to parsed content
- Time matching tolerance: Allows 10-second tolerance for date-based URL matching