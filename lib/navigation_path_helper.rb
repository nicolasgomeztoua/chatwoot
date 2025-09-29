require 'uri'

module NavigationPathHelper
  INTERNAL_QUERY_KEYS = %w[website_token].freeze
  INTERNAL_QUERY_PREFIXES = %w[cw_].freeze

  module_function

  def sanitized_path(url)
    return if url.nil? || url.empty?

    uri = URI.parse(url)
    build_path(uri)
  rescue URI::InvalidURIError
    url
  end

  def build_path(uri)
    path = uri.path
    path = '/' if path.nil? || path.empty?

    query = sanitize_query(uri.query)
    fragment = uri.fragment

    result = path.dup
    result = "#{result}?#{query}" if query && !query.empty?
    result = "#{result}##{fragment}" if fragment && !fragment.empty?
    result.empty? ? '/' : result
  end

  def sanitize_query(query)
    return if query.nil? || query.empty?

    filtered_params = URI.decode_www_form(query).reject do |key, _|
      internal_query_key?(key)
    end
    return if filtered_params.empty?

    URI.encode_www_form(filtered_params)
  end

  def internal_query_key?(key)
    return true if key.nil? || key.empty?

    INTERNAL_QUERY_KEYS.include?(key) || INTERNAL_QUERY_PREFIXES.any? { |prefix| key.start_with?(prefix) }
  end
end
