# frozen_string_literal: true

source "https://rubygems.org"

ruby File.read(".ruby-version").strip if File.exist?(".ruby-version")

gem "base64"

group :development, :test do
  gem "rspec"
  gem "rubocop"
  gem "rubocop-performance"
  gem "rubocop-rspec"
  gem "webmock"
end
