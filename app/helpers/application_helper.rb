module ApplicationHelper
  include Pagy::Frontend

  def product_name
    Rails.configuration.x.product_name
  end

  def brand_name
    Rails.configuration.x.brand_name
  end

  def styled_form_with(**options, &block)
    options[:builder] = StyledFormBuilder
    form_with(**options, &block)
  end

  def icon(key, size: "md", color: "default", custom: false, as_button: false, **opts)
    extra_classes = opts.delete(:class)
    sizes = { xs: "w-3 h-3", sm: "w-4 h-4", md: "w-5 h-5", lg: "w-6 h-6", xl: "w-7 h-7", "2xl": "w-8 h-8" }
    colors = { default: "fg-gray", white: "fg-inverse", success: "text-success", warning: "text-warning", destructive: "text-destructive", current: "text-current" }

    icon_classes = class_names(
      "shrink-0",
      sizes[size.to_sym],
      colors[color.to_sym],
      extra_classes
    )

    if custom
      inline_svg_tag("#{key}.svg", class: icon_classes, **opts)
    elsif as_button
      render DS::Button.new(variant: "icon", class: extra_classes, icon: key, size: size, type: "button", **opts)
    else
      lucide_icon(key, class: icon_classes, **opts)
    end
  end

  # Convert alpha (0-1) to 8-digit hex (00-FF)
  def hex_with_alpha(hex, alpha)
    alpha_hex = (alpha * 255).round.to_s(16).rjust(2, "0")
    "#{hex}#{alpha_hex}"
  end

  def title(page_title)
    content_for(:title) { page_title }
  end

  def header_title(page_title)
    content_for(:header_title) { page_title }
  end

  def header_description(page_description)
    content_for(:header_description) { page_description }
  end

  def page_active?(path)
    normalized_request_path = normalize_active_path(request.path)
    normalized_path = normalize_active_path(path)

    normalized_request_path == normalized_path ||
      (normalized_request_path.start_with?(normalized_path) && normalized_path != "/")
  end

  # Wrapper around I18n.l to support custom date formats
  def format_date(object, format = :default, options = {})
    date = object.to_date

    format_code = options[:format_code] || Current.family&.date_format

    if format_code.present?
      date.strftime(format_code)
    else
      I18n.l(date, format: format, **options)
    end
  end


  def family_moniker
    Current.family&.moniker_label || "Family"
  end

  def family_moniker_downcase
    family_moniker.downcase
  end

  def family_moniker_plural
    Current.family&.moniker_label_plural || "Families"
  end

  def family_moniker_plural_downcase
    family_moniker_plural.downcase
  end

  def format_money(number_or_money, options = {})
    return nil unless number_or_money

    Money.new(number_or_money).format(options)
  end

  def totals_by_currency(collection:, money_method:, separator: " | ", negate: false)
    collection.group_by(&:currency)
              .transform_values { |item| calculate_total(item, money_method, negate) }
              .map { |_currency, money| format_money(money) }
              .join(separator)
  end

  def show_super_admin_bar?
    if params[:admin].present?
      cookies.permanent[:admin] = params[:admin]
    end

    cookies[:admin] == "true"
  end

  def default_ai_model
    # Always return a valid model, never nil or empty
    # Delegates to Chat.default_model for consistency
    Chat.default_model
  end
  def omniauth_provider_path(provider_name)
    script_name = request.script_name.to_s.sub(%r{/+\z}, "")
    "#{script_name}/auth/#{provider_name}"
  end

  def ingress_prefixed_path(path)
    return path if path.blank?

    script_name = request.script_name.to_s.sub(%r{/+\z}, "")
    return path if script_name.blank?

    return path if path.start_with?("http://", "https://", "//")

    normalized_path = path.start_with?("/") ? path : "/#{path}"
    return normalized_path if normalized_path.start_with?("#{script_name}/")

    "#{script_name}#{normalized_path}"
  end

  def ingress_asset_path(source, **options)
    ingress_prefixed_path(asset_path(source, **options))
  end

  def ingress_javascript_importmap_tags
    tags = javascript_importmap_tags
    return tags if request.script_name.blank?

    fragment = Nokogiri::HTML::DocumentFragment.parse(tags)

    importmap = fragment.at_css("script[type='importmap']")
    if importmap&.content.present?
      data = JSON.parse(importmap.content)
      data["imports"] = prefix_importmap_values(data["imports"]) if data["imports"].is_a?(Hash)

      if data["scopes"].is_a?(Hash)
        data["scopes"] = data["scopes"].transform_values do |scoped_imports|
          prefix_importmap_values(scoped_imports)
        end
      end

      importmap.content = JSON.generate(data)
    end

    fragment.css("link[rel='modulepreload']").each do |node|
      href = node["href"]
      next if href.blank?

      node["href"] = ingress_prefixed_path(href)
    end

    fragment.to_html.html_safe
  end
  # Renders Markdown text using Redcarpet
  def markdown(text)
    return "" if text.blank?

    renderer = Redcarpet::Render::HTML.new(
      hard_wrap: true,
      link_attributes: { target: "_blank", rel: "noopener noreferrer" }
    )

    markdown = Redcarpet::Markdown.new(
      renderer,
      autolink: true,
      tables: true,
      fenced_code_blocks: true,
      strikethrough: true,
      superscript: true,
      underline: true,
      highlight: true,
      quote: true,
      footnotes: true
    )

    markdown.render(text).html_safe
  end

  # Formats quantity with adaptive precision based on the value size.
  # Shows more decimal places for small quantities (common with crypto).
  #
  # @param qty [Numeric] The quantity to format
  # @param max_precision [Integer] Maximum precision for very small numbers
  # @return [String] Formatted quantity with appropriate precision
  def format_quantity(qty)
    return "0" if qty.nil? || qty.zero?

    abs_qty = qty.abs

    precision = if abs_qty >= 1
      1     # "10.5"
    elsif abs_qty >= 0.01
      2     # "0.52"
    elsif abs_qty >= 0.0001
      4     # "0.0005"
    else
      8     # "0.00000052"
    end

    # Use strip_insignificant_zeros to avoid trailing zeros like "0.50000000"
    number_with_precision(qty, precision: precision, strip_insignificant_zeros: true)
  end

  private
    def normalize_active_path(value)
      return "/" if value.blank?

      path = value.to_s

      if path.start_with?("http://", "https://")
        begin
          path = URI.parse(path).path
        rescue URI::InvalidURIError
          # Keep the original path as-is for non-parseable inputs.
        end
      end

      script_name = request.script_name.to_s
      if script_name.present? && path.start_with?(script_name)
        path = path.delete_prefix(script_name)
        path = "/#{path}" unless path.start_with?("/")
      end

      path = "/#{path}" unless path.start_with?("/")
      path = path.sub(%r{/+\z}, "")
      path = "/" if path.empty?

      path
    end

    def prefix_importmap_values(imports)
      return imports unless imports.is_a?(Hash)

      imports.transform_values do |value|
        next value unless value.is_a?(String)

        ingress_prefixed_path(value)
      end
    end

    def calculate_total(item, money_method, negate)
      # Filter out transfer-type transactions from entries
      # Only Entry objects have entryable transactions, Account objects don't
      items = item.reject do |i|
        i.is_a?(Entry) &&
        i.entryable.is_a?(Transaction) &&
        i.entryable.transfer?
      end
      total = items.sum(&money_method)
      negate ? -total : total
    end
end
