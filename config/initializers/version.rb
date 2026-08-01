module Sure
  # Sure26 is an independent modified fork of Sure. To satisfy AGPLv3, the
  # running app links users to the corresponding source of the exact deployed
  # version. Operators running their own fork can point these links at their
  # source by setting SURE_SOURCE_REPO to "owner/repo".
  SOURCE_REPO = ENV.fetch("SURE_SOURCE_REPO", "aso42244/sure26").freeze

  class << self
    def version
      Semver.new(semver)
    end

    def commit_sha
      if Rails.env.production?
        ENV["BUILD_COMMIT_SHA"]
      else
        `git rev-parse HEAD`.chomp
      end
    rescue Errno::ENOENT
      nil
    end

    def source_repo_url
      "https://github.com/#{SOURCE_REPO}"
    end

    def release_url
      "#{source_repo_url}/releases/tag/#{version.to_release_tag}"
    end

    def commit_url
      commit_sha.present? ? "#{source_repo_url}/commit/#{commit_sha}" : source_repo_url
    end

    # The link that offers the corresponding source for the exact deployed
    # version: the precise commit when known, otherwise the release tag.
    def source_url
      commit_sha.present? ? commit_url : release_url
    end

    private
      def semver
        stripped_content = Rails.root.join(".sure-version").read.strip
        stripped_content.presence || "n/a: #{commit_sha}"
      rescue Errno::ENOENT
        "n/a: #{commit_sha || 'unknown'}"
      end
  end
end
