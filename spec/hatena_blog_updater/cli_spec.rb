# frozen_string_literal: true

require "spec_helper"
require "tempfile"
require_relative "../../hatena_blog_updater"

RSpec.describe HatenaBlogUpdater::CLI do
  let(:api_key) { "test_api_key_12345" }
  let(:cli) { described_class.new }
  let(:entry_id) { "13574176438046791234" }
  let(:update_result) do
    {
      title: "Updated Title",
      url: "https://test-blog.hatenablog.com/entry/2024/01/01/123456",
      edit_url: "https://blog.hatena.ne.jp/test-user/test-blog.hatenablog.com/edit?entry=#{entry_id}",
      published: "2024-01-01T12:34:56+09:00"
    }
  end

  before do
    ENV["HATENA_API_KEY"] = api_key
  end

  after do
    ENV.delete("HATENA_API_KEY")
  end

  describe ".run" do
    it "delegates to instance run method" do
      args = ["-i", entry_id, "-t", "Test", "-f", "test.md"]
      expect_any_instance_of(described_class).to receive(:run).with(args)

      described_class.run(args)
    end
  end

  describe "#run" do
    let(:temp_file) do
      file = Tempfile.new(["test", ".md"])
      file.write("# Updated Content\n\nThis is updated content.")
      file.close
      file
    end

    after do
      temp_file&.unlink
    end

    context "with valid options using entry ID for draft" do
      before do
        allow_any_instance_of(HatenaBlogUpdater).to receive(:update_entry).and_return(update_result)
      end

      it "outputs success message with draft status" do
        output = capture_stdout { cli.run(["-i", entry_id, "-t", "Updated Title", "-f", temp_file.path]) }

        expect(output).to include("更新が完了しました（下書き）")
        expect(output).to include("タイトル: Updated Title")
        expect(output).to include("URL: #{update_result[:edit_url]}")
      end

      it "calls update_entry with draft: true by default" do
        # rubocop:disable RSpec/StubbedMock
        expect_any_instance_of(HatenaBlogUpdater).to receive(:update_entry)
          .with(entry_url_or_id: entry_id, title: "Updated Title", content: include("Updated Content"), draft: true)
          .and_return(update_result)
        # rubocop:enable RSpec/StubbedMock

        capture_stdout { cli.run(["-i", entry_id, "-t", "Updated Title", "-f", temp_file.path]) }
      end
    end

    context "with valid options using URL" do
      let(:entry_url) { "https://test-blog.hatenablog.com/entry/2024/01/01/123456" }

      before do
        allow_any_instance_of(HatenaBlogUpdater).to receive(:update_entry).and_return(update_result)
      end

      it "outputs success message" do
        output = capture_stdout { cli.run(["-u", entry_url, "-t", "Updated Title", "-f", temp_file.path]) }

        expect(output).to include("更新が完了しました（下書き）")
        expect(output).to include("タイトル: Updated Title")
      end

      it "calls update_entry with URL" do
        # rubocop:disable RSpec/StubbedMock
        expect_any_instance_of(HatenaBlogUpdater).to receive(:update_entry)
          .with(entry_url_or_id: entry_url, title: "Updated Title", content: include("Updated Content"), draft: true)
          .and_return(update_result)
        # rubocop:enable RSpec/StubbedMock

        capture_stdout { cli.run(["-u", entry_url, "-t", "Updated Title", "-f", temp_file.path]) }
      end
    end

    context "with --publish option" do
      before do
        allow_any_instance_of(HatenaBlogUpdater).to receive(:update_entry).and_return(update_result)
      end

      it "outputs success message with published status" do
        output = capture_stdout { cli.run(["-i", entry_id, "-t", "Updated Title", "-f", temp_file.path, "-p"]) }

        expect(output).to include("更新が完了しました（公開）")
        expect(output).to include("URL: #{update_result[:url]}")
      end

      it "calls update_entry with draft: false" do
        # rubocop:disable RSpec/StubbedMock
        expect_any_instance_of(HatenaBlogUpdater).to receive(:update_entry)
          .with(entry_url_or_id: entry_id, title: "Updated Title", content: include("Updated Content"), draft: false)
          .and_return(update_result)
        # rubocop:enable RSpec/StubbedMock

        capture_stdout { cli.run(["-i", entry_id, "-t", "Updated Title", "-f", temp_file.path, "--publish"]) }
      end
    end

    context "with --help option" do
      it "displays help and exits" do
        expect { cli.run(["--help"]) }.to output(/使用方法/).to_stdout.and raise_error(SystemExit)
      end
    end

    context "when both URL and ID are specified" do
      it "outputs error message and exits" do
        expect do
          cli.run(["-u", "https://example.com/entry/123", "-i", entry_id, "-t", "Test", "-f", temp_file.path])
        end.to output(/URLとIDは同時に指定できません/).to_stderr.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context "when neither URL nor ID is specified" do
      it "outputs error message and exits" do
        expect do
          cli.run(["-t", "Test Title", "-f", temp_file.path])
        end.to output(/URLまたはID.*は必須です/).to_stderr.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context "when title is missing" do
      it "outputs error message and exits" do
        expect do
          cli.run(["-i", entry_id, "-f", temp_file.path])
        end.to output(/タイトル.*必須/).to_stderr.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context "when file is missing" do
      it "outputs error message and exits" do
        expect do
          cli.run(["-i", entry_id, "-t", "Test Title"])
        end.to output(/ファイル.*必須/).to_stderr.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context "when file does not exist" do
      it "outputs error message and exits" do
        expect do
          cli.run(["-i", entry_id, "-t", "Test Title", "-f", "/nonexistent/file.md"])
        end.to output(/ファイルが見つかりません/).to_stderr.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end

    context "when API error occurs" do
      before do
        allow_any_instance_of(HatenaBlogUpdater).to receive(:update_entry)
          .and_raise("APIリクエストが失敗しました: 401 Unauthorized")
      end

      it "outputs error message and exits" do
        expect do
          cli.run(["-i", entry_id, "-t", "Test Title", "-f", temp_file.path])
        end.to output(/エラー: APIリクエストが失敗しました/).to_stderr.and raise_error(SystemExit) { |error|
          expect(error.status).to eq(1)
        }
      end
    end
  end
end
