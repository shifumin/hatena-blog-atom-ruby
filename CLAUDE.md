# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Ruby scripts for fetching, posting, and updating blog entries on Hatena Blog using the AtomPub API. The project consists of three main scripts:

- `hatena_blog_fetcher.rb` - Fetch blog entries by URL
- `hatena_blog_poster.rb` - Post new blog entries
- `hatena_blog_updater.rb` - Update existing blog entries

## Development Commands

Ruby and dependencies are managed via [mise](https://mise.jdx.dev/). All Ruby/Bundler commands MUST be prefixed with `mise exec --` so the correct toolchain is used.

### Dependencies
```bash
mise exec -- bundle install
```

### Testing & Linting
```bash
# Run RuboCop linter
mise exec -- bundle exec rubocop

# Auto-fix linting issues
mise exec -- bundle exec rubocop -a

# Run RSpec tests
mise exec -- bundle exec rspec

# Run specific test file
mise exec -- bundle exec rspec spec/hatena_blog_fetcher_spec.rb
```

### Running the Scripts

All scripts are invoked with `mise exec -- ruby <script>`. Direct invocation (`./script.rb`) is unreliable because only `hatena_blog_fetcher.rb` has the executable bit set; `hatena_blog_poster.rb` and `hatena_blog_updater.rb` do not.

#### Fetcher (fetch blog entries)
```bash
mise exec -- ruby hatena_blog_fetcher.rb [URL]
mise exec -- ruby hatena_blog_fetcher.rb -r [URL]  # Raw Markdown content only
mise exec -- ruby hatena_blog_fetcher.rb -t [URL]  # Title only
mise exec -- ruby hatena_blog_fetcher.rb -d [URL]  # Date/time only
mise exec -- ruby hatena_blog_fetcher.rb -u [URL]  # URL only
```

Fetcher CLI options:

| Option | Description |
|--------|-------------|
| `-r, --raw` | Output raw Markdown content only |
| `-t, --title` | Output title only |
| `-d, --date` | Output publication datetime only |
| `-u, --url` | Output URL only |
| `-h, --help` | Display help message |

Without any of `-r`/`-t`/`-d`/`-u`, the full formatted entry (title / datetime / URL / categories / draft status / entry ID / Markdown body) is printed.

#### Poster (create new entries)
```bash
mise exec -- ruby hatena_blog_poster.rb -t "Title" -f content.md      # Post as draft
mise exec -- ruby hatena_blog_poster.rb -t "Title" -f content.md -p   # Publish immediately
```

#### Updater (update existing entries)
```bash
# Update by entry ID (defaults to draft)
mise exec -- ruby hatena_blog_updater.rb -i ENTRY_ID -t "Title" -f content.md

# Update by URL (date-based, entry-ID, or edit URL accepted)
mise exec -- ruby hatena_blog_updater.rb -u URL -t "Title" -f content.md

# Update and publish
mise exec -- ruby hatena_blog_updater.rb -i ENTRY_ID -t "Title" -f content.md -p

# Set categories explicitly (comma-separated)
mise exec -- ruby hatena_blog_updater.rb -i ENTRY_ID -t "Title" -f content.md -c "Ruby,API"

# Override the publication datetime (ISO 8601)
mise exec -- ruby hatena_blog_updater.rb -i ENTRY_ID -t "Title" -f content.md --updated "2024-01-01T12:34:56+09:00"

# Preserve existing categories AND publication datetime when not explicitly given
mise exec -- ruby hatena_blog_updater.rb -i ENTRY_ID -t "Title" -f content.md --preserve
```

Updater CLI options:

| Option | Description |
|--------|-------------|
| `-u, --url URL` | Entry URL (mutually exclusive with `-i`) |
| `-i, --id ID` | Entry ID (mutually exclusive with `-u`) |
| `-t, --title TITLE` | Article title (required) |
| `-f, --file FILE` | Markdown file path (required) |
| `-p, --publish` | Publish the entry. **Without `-p`, the entry becomes a draft on save** — even if the entry was previously published. To keep an already-published entry public, you must pass `-p` |
| `-c, --categories CATEGORIES` | Comma-separated categories. When given, replaces existing categories; the new value wins over `--preserve` |
| `--updated DATETIME` | Publication datetime (ISO 8601). When given, overrides existing datetime; the new value wins over `--preserve` |
| `--preserve` | For each of `categories` / `updated` *not* explicitly passed on the CLI, fetch the existing entry and reuse its value. Explicitly passed `-c` / `--updated` always take precedence |

Combination rules (Updater):

- `-c "X,Y" --preserve` → categories become `X, Y` (explicit `-c` wins); datetime is preserved from the existing entry
- `--updated "..." --preserve` → datetime is the explicit value; categories preserved from existing entry
- `-c "X,Y" --updated "..." --preserve` → both explicit values win; `--preserve` is effectively a no-op
- `--preserve` alone → both categories and datetime are reused from the existing entry
- Neither `-c` nor `--preserve` → categories become **empty** (existing categories are dropped)
- Neither `--updated` nor `--preserve` → datetime becomes **the current time at request** (existing datetime is overwritten)

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
- See `.ruby-version` (managed by mise via `mise.toml`)
- `mise.toml` ships placeholder env values; put real credentials in `mise.local.toml` (gitignored) or export them in the shell

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
3. Edit URLs: `https://blog.hatena.ne.jp/{user}/{blog}/edit?entry={entry_id}` (Hatena admin URL — `extract_entry_id` reads the entry ID from the `entry` query parameter; supported by both `hatena_blog_fetcher.rb` and `hatena_blog_updater.rb`)

For date-based URLs, scripts paginate through the entry list and pick the best match using a scoring function:
- Exact date match is preferred; otherwise the closest date is used.
- Time component (HHMMSS) is compared against the entry's apparent publish time, with a **±1 hour tolerance** to absorb timezone/skew.
- Pagination follows the Atom `link rel="next"` until either the entry is found or pages run out.

The scoring helpers live in `find_matching_entries_in_page`, `calculate_entry_match_score`, `calculate_date_diff`, and `calculate_time_diff` in both `hatena_blog_fetcher.rb` and `hatena_blog_updater.rb`.

### Key Components

All three classes validate `HATENA_ID` / `HATENA_BLOG_ID` / `HATENA_API_KEY` in `initialize` (via the private `validate_credentials!` method) and raise `ArgumentError` if any is missing or empty. There is no lazy/dry-run path that skips this check today — instantiating any of these classes without credentials always raises.

#### HatenaBlogFetcher class
Fetches blog entries from the API:
- `fetch_entry(url)`: Fetches a single entry by URL. Returns a `Hash` with keys `:title`, `:content`, `:published`, `:url`, `:categories`, `:draft`, `:entry_id`.
- `find_entry_by_date(date, time)`: Searches entries by date/time with pagination, returns the matched `entry` element or `nil`.

#### HatenaBlogPoster class
Posts new blog entries:
- `post_entry(title:, content:, draft: false)`: Creates a new entry. Returns a `Hash` with keys `:title`, `:url`, `:edit_url`, `:published`. Raises `RuntimeError` on non-2xx HTTP responses.

#### HatenaBlogUpdater class
Updates existing blog entries:
- `update_entry(entry_url_or_id:, title:, content:, draft: false, categories: [], updated: nil, preserve: false)`: Updates an existing entry. Returns a `Hash` with keys `:title`, `:url`, `:edit_url`, `:published`. Raises `RuntimeError` if the entry is not found or the API request fails.
- `fetch_existing_entry(entry_id)`: Fetches existing entry for preserve mode. Returns a `Hash` with keys `:categories` (`Array<String>`) and `:updated` (`String`, ISO 8601).
- Supports entry ID, entry URL, and date-based URL formats.
- `preserve: true` only fills in `categories` / `updated` when the caller did NOT pass them; explicit values always win (see "Combination rules" above).

#### CLI classes
Each script has an inner `CLI` class handling command-line interaction:
- `HatenaBlogFetcher::CLI`
- `HatenaBlogPoster::CLI`
- `HatenaBlogUpdater::CLI`

Each `CLI` class follows the same internal layout: `parse_options` → `create_option_parser` → `define_options` → `validate_options!`, with a `handle_error` for top-level rescue. Adding a new flag means editing `define_options` (and `validate_options!` if cross-flag rules apply).

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
- Uses `# frozen_string_literal: true` magic comment in every Ruby source file
- Public methods carry YARD comments (`@param`, `@return`, `@raise`); preserve this convention when adding methods
- Follows Ruby community conventions
- RuboCop, RuboCop-Performance, and RuboCop-RSpec configured (see `.rubocop.yml`)
- Tests cover **public interfaces only** (not private methods); each test should hit normal, error, and edge cases
