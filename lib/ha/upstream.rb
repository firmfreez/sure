require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "securerandom"
require "time"

module Ha
  # Git/file operations only. This tool never boots Rails, changes a database,
  # publishes a branch, or resolves conflicts by choosing one side wholesale.
  class Upstream
    class Error < StandardError; end

    CONFIG_PATH = "config/ha/upstream.json"
    LOCK_PATH = "config/ha/migrations.lock.json"

    def initialize(root:, output: $stdout)
      @root = Pathname(root).expand_path
      @output = output
    end

    def check
      errors = protected_errors
      lock = read_json(LOCK_PATH)
      errors << "Migration review belongs to a different upstream commit" unless lock["upstream_commit"] == baseline
      errors.concat(migration_changes(lock.fetch("files"), migration_hashes))
      errors << "Pinned upstream is not an ancestor of HEAD" unless ancestor?(baseline, "HEAD")
      raise Error, errors.join("\n") if errors.any?

      @output.puts "PASS: upstream ancestry, protected HA migrations and migration review are consistent."
    end

    def report(ref)
      target = commit(ref)
      raise Error, "Target must descend from the pinned upstream commit" unless ancestor?(baseline, target)

      upstream_files = git("diff", "--name-only", baseline, target).lines.map(&:strip)
      fork_files = git("diff", "--name-only", baseline, "HEAD").lines.map(&:strip)
      migrations = git("diff", "--name-status", baseline, target, "--", "db/migrate").strip
      overlapping = (upstream_files & fork_files).sort
      <<~REPORT
        # Upstream update review

        - Current upstream: `#{baseline}`
        - Candidate: `#{target}`
        - New upstream commits: #{git("rev-list", "--count", "#{baseline}..#{target}").strip}

        ## Migration changes requiring review

        ```text
        #{migrations.empty? ? "None" : migrations}
        ```

        Review the full SQL/Ruby changes, including backdated migrations. A clean
        rebase does not establish data compatibility. Rehearse on a private copy
        of the installed database before deploying.

        ## Files modified by both upstream and this fork

        #{overlapping.empty? ? "None" : overlapping.map { |file| "- `#{file}`" }.join("\n")}

        No source branch, database or deployment was changed by this report.
      REPORT
    end

    def prepare(ref = nil)
      check
      raise Error, "Commit or stash local changes first" unless git("status", "--porcelain").strip.empty?
      raise Error, "Merge commits in the overlay require manual review before rebasing" unless git("rev-list", "--merges", "#{baseline}..HEAD").strip.empty?

      if ref.nil?
        git("fetch", "--no-tags", config.fetch("repository"), "main")
        ref = "FETCH_HEAD"
      end
      target = commit(ref)
      raise Error, "Already based on this upstream commit" if target == baseline
      review = report(target)
      original = commit("HEAD")
      stamp = "#{Time.now.utc.strftime('%Y%m%d-%H%M%S')}-#{SecureRandom.hex(3)}"
      backup = "backup/ha-before-upstream-#{stamp}"
      branch = "ha/upstream-#{target[0, 12]}-#{stamp}"
      directory = @root.join(".ha-upgrade-backups", "upstream", stamp)
      worktree = directory.join("worktree")
      FileUtils.mkdir_p(directory, mode: 0o700)
      git("branch", backup, original)
      git("bundle", "create", directory.join("before.bundle").to_s, "refs/heads/#{backup}")
      git("bundle", "verify", directory.join("before.bundle").to_s)
      File.write(directory.join("review.md"), review)
      File.write(directory.join("update.json"), JSON.pretty_generate({ original: original, target: target, backup: backup, branch: branch, worktree: worktree.to_s }) + "\n")
      git("worktree", "add", "-b", branch, worktree.to_s, original)
      @output.puts "Backup: #{backup}\nReview: #{directory.join('review.md')}\nWorktree: #{worktree}"
      stdout, stderr, status = Open3.capture3("git", "rebase", "--onto", target, baseline, chdir: worktree.to_s)
      @output.puts stdout, stderr
      unless status.success?
        raise Error, "Rebase stopped in #{worktree}. Resolve conflicts there and run git rebase --continue (or --abort). The original branch is unchanged."
      end
      @output.puts "Review migrations in the worktree, then run: bin/ha-upstream record-review #{target} --reviewed-migrations"
      @output.puts "Run HA compatibility and full tests before committing/publishing. Nothing was pushed."
      worktree
    end

    def record_review(ref, reviewed_migrations: false)
      raise Error, "Read the migration diff and explicitly pass --reviewed-migrations" unless reviewed_migrations
      target = commit(ref)
      raise Error, "Review target must be an upstream descendant already incorporated into HEAD" unless ancestor?(baseline, target) && ancestor?(target, "HEAD")
      raise Error, "Finish the rebase and resolve all conflicts first" if rebasing? || !git("diff", "--name-only", "--diff-filter=U").strip.empty?
      errors = protected_errors
      raise Error, errors.join("\n") if errors.any?

      updated = config.merge("upstream_commit" => target)
      write_json(LOCK_PATH, { "upstream_commit" => target, "files" => migration_hashes })
      write_json(CONFIG_PATH, updated)
      @config = updated
      @output.puts "Recorded migration review. Inspect and commit both config/ha files; this does not certify the production database."
      check
    end

    private
      def config
        @config ||= read_json(CONFIG_PATH)
      end

      def baseline
        value = config.fetch("upstream_commit")
        raise Error, "Invalid upstream SHA" unless value.match?(/\A[0-9a-f]{40}\z/)
        value
      end

      def migration_hashes
        @root.glob("db/migrate/*.rb").sort.to_h { |path| [ path.basename.to_s, Digest::SHA256.file(path).hexdigest ] }
      end

      def protected_errors
        files = migration_hashes
        config.fetch("protected_migrations").filter_map do |name, expected|
          "Protected HA migration changed or disappeared: #{name}. Restore it or explicitly review the protection policy; record-review cannot accept this automatically." unless files[name] == expected
        end
      end

      def migration_changes(expected, actual)
        (expected.keys | actual.keys).sort.filter_map do |name|
          next if expected[name] == actual[name]
          status = !expected.key?(name) ? "added" : (!actual.key?(name) ? "removed" : "modified")
          "Unreviewed migration #{status}: #{name}"
        end
      end

      def rebasing?
        %w[rebase-merge rebase-apply].any? { |path| @root.join(git("rev-parse", "--git-path", path).strip).directory? }
      end

      def read_json(path)
        JSON.parse(@root.join(path).read)
      end

      def write_json(path, value)
        @root.join(path).write(JSON.pretty_generate(value) + "\n")
      end

      def commit(ref)
        git("rev-parse", "--verify", "--end-of-options", "#{ref}^{commit}").strip
      end

      def ancestor?(older, newer)
        _stdout, _stderr, status = Open3.capture3("git", "-C", @root.to_s, "merge-base", "--is-ancestor", older, newer)
        status.success?
      end

      def git(*arguments)
        stdout, stderr, status = Open3.capture3("git", "-C", @root.to_s, *arguments)
        raise Error, "git #{arguments.first} failed: #{stderr.strip}" unless status.success?
        stdout
      end
  end
end
