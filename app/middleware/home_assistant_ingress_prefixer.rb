# frozen_string_literal: true

# Applies Home Assistant ingress path prefix so URL helpers and redirects
# generate links that stay within the ingress mount point.
class HomeAssistantIngressPrefixer
  def initialize(app)
    @app = app
  end

  def call(env)
    ingress_prefix = extract_ingress_prefix(env)
    return @app.call(env) unless ingress_prefix

    env["SCRIPT_NAME"] = merge_script_names(env["SCRIPT_NAME"], ingress_prefix)
    env["PATH_INFO"] = strip_prefix(env["PATH_INFO"], ingress_prefix)

    @app.call(env)
  end

  private
    def extract_ingress_prefix(env)
      candidates = [
        env["HTTP_X_INGRESS_PATH"],
        env["HTTP_X_FORWARDED_PREFIX"]&.split(",")&.first,
        ENV["HA_INGRESS_PATH"]
      ]

      candidates.each do |value|
        normalized = normalize_prefix(value)
        return normalized if normalized
      end

      nil
    end

    def normalize_prefix(value)
      return nil if value.nil?

      prefix = value.to_s.strip
      return nil if prefix.empty?

      prefix = "/#{prefix}" unless prefix.start_with?("/")
      prefix = prefix.sub(%r{/+\z}, "")
      return nil if prefix.empty? || prefix == "/"

      prefix
    end

    def merge_script_names(existing_script_name, ingress_prefix)
      existing = existing_script_name.to_s
      return ingress_prefix if existing.empty?
      return existing if existing.start_with?(ingress_prefix)

      "#{existing.sub(%r{/+\z}, "")}#{ingress_prefix}"
    end

    def strip_prefix(path_info, ingress_prefix)
      path = path_info.to_s
      return path if path.empty?
      return path unless path.start_with?(ingress_prefix)

      stripped = path.delete_prefix(ingress_prefix)
      stripped.empty? ? "/" : stripped
    end
end
