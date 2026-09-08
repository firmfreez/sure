require "minitest/autorun"
require "tmpdir"
require "stringio"
require_relative "../../lib/ha/upstream"

class HaUpstreamTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("ha-upstream-test")
    git("init", "-b", "main")
    git("config", "user.email", "test@example.invalid")
    git("config", "user.name", "HA test")
    FileUtils.mkdir_p("#{@root}/db/migrate")
    FileUtils.mkdir_p("#{@root}/config/ha")
    File.write("#{@root}/db/migrate/20260101000000_example.rb", "# migration\n")
    git("add", ".")
    git("commit", "-m", "Initial upstream")
    @baseline = git("rev-parse", "HEAD").strip
    hashes = { "20260101000000_example.rb" => Digest::SHA256.hexdigest("# migration\n") }
    write_json("upstream.json", { upstream_commit: @baseline, protected_migrations: hashes })
    write_json("migrations.lock.json", { upstream_commit: @baseline, files: hashes })
    File.write("#{@root}/.gitignore", "/.ha-upgrade-backups/\n")
    git("add", ".")
    git("commit", "-m", "Add HA overlay")
    @tool = Ha::Upstream.new(root: @root, output: StringIO.new)
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_detects_backdated_migrations
    File.write("#{@root}/db/migrate/20250101000000_backdated.rb", "# new\n")
    assert_match(/Unreviewed migration added/, assert_raises(Ha::Upstream::Error) { @tool.check }.message)
  end

  def test_review_cannot_accept_modified_protected_migration
    File.write("#{@root}/db/migrate/20260101000000_example.rb", "# changed\n")
    assert_match(/Protected HA migration/, assert_raises(Ha::Upstream::Error) do
      @tool.record_review(@baseline, reviewed_migrations: true)
    end.message)
  end

  def test_prepare_preserves_original_checkout_and_creates_reviewable_worktree
    original = git("rev-parse", "HEAD").strip
    git("checkout", "-b", "candidate", @baseline)
    File.write("#{@root}/upstream.txt", "new upstream\n")
    git("add", ".")
    git("commit", "-m", "Update upstream")
    target = git("rev-parse", "HEAD").strip
    git("checkout", "main")

    worktree = @tool.prepare(target)

    assert_equal original, git("rev-parse", "HEAD").strip
    assert_equal "", git("status", "--porcelain").strip
    assert worktree.join("upstream.txt").file?
    assert worktree.parent.join("before.bundle").file?
    updated = Ha::Upstream.new(root: worktree, output: StringIO.new)
    updated.record_review(target, reviewed_migrations: true)
    updated.check
  end

  private
    def write_json(name, value)
      File.write("#{@root}/config/ha/#{name}", JSON.generate(value))
    end

    def git(*args)
      output, status = Open3.capture2e("git", "-C", @root, *args)
      raise output unless status.success?
      output
    end
end
