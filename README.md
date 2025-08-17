# hatena-blog-atom-ruby

A Ruby script for fetching blog entries from Hatena Blog using the AtomPub API.

## Features

- Fetch individual blog posts by URL
- Support for both date-based URLs and entry ID URLs
- Multiple output formats (full, raw markdown, title only, date only)
- WSSE authentication for secure API access
- Command-line interface with options
- Automatic removal of trailing whitespace from content
- Pagination support for searching entries by date
- Time tolerance matching for date-based URLs (±10 seconds)

## Prerequisites

- Ruby 3.4.5 or higher
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

You can obtain your API key from your Hatena Blog account settings.

## Usage

### Basic Usage

Fetch a blog entry by URL:
```bash
./hatena_blog_fetcher.rb https://shifumin.hatenadiary.com/entry/2024/01/01/123456
```

### Command-line Options

- `-r, --raw` - Output raw Markdown content only
- `-t, --title` - Output title only
- `-d, --date` - Output publication date only
- `-h, --help` - Display help message

### Examples

```bash
# Get full entry information (default)
./hatena_blog_fetcher.rb https://shifumin.hatenadiary.com/entry/2024/01/01/123456

# Get only the raw Markdown content
./hatena_blog_fetcher.rb -r https://shifumin.hatenadiary.com/entry/2024/01/01/123456

# Get only the title
./hatena_blog_fetcher.rb -t https://shifumin.hatenadiary.com/entry/2024/01/01/123456

# Get only the publication date
./hatena_blog_fetcher.rb -d https://shifumin.hatenadiary.com/entry/2024/01/01/123456
```

## Supported URL Formats

The script supports two types of Hatena Blog URLs:

1. **Date-based URLs**: `https://example.hatenadiary.com/entry/YYYY/MM/DD/HHMMSS`
2. **Entry ID URLs**: `https://example.hatenadiary.com/entry/YYYYMMDD/1234567890`

## Development

### Project Structure

- `hatena_blog_fetcher.rb` - Main script containing HatenaBlogFetcher and CommandLineInterface classes
- `spec/` - RSpec test files
  - `hatena_blog_fetcher_spec.rb` - Tests for HatenaBlogFetcher class
  - `command_line_interface_spec.rb` - Tests for CommandLineInterface class
- `Gemfile` - Ruby dependencies
- `.rubocop.yml` - RuboCop configuration for code style

### Running Tests

```bash
# Run all tests
rspec

# Run specific test file
rspec spec/hatena_blog_fetcher_spec.rb

# Run with detailed output
rspec --format documentation
```

### Linting

```bash
# Check code style
rubocop

# Auto-fix issues
rubocop -a

# Check specific file
rubocop hatena_blog_fetcher.rb
```

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

### Date-based URL Search
For date-based URLs, the script:
1. Fetches the entry list from the API
2. Iterates through pages if necessary
3. Matches entries by comparing timestamps (with 10-second tolerance)
4. Retrieves the full entry details once found

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
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is open source and available under the [MIT License](LICENSE).