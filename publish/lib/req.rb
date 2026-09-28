class Req
  class ResponseError < RuntimeError
    attr_reader :status

    def initialize(message, status:)
      @status = status
      super(message)
    end
  end

  class << self
    def call(
      url:,
      method: :get,
      headers: {},
      params: {},
      payload: {},
      body: nil,
      quiet: true,
      content: :json,
      **_
    )
      headers = { "Content-Type" => "application/json" }.merge(headers)
      puts "#{method.upcase} #{url} #{params.present? || payload.present? ? params.merge(payload) : nil}".blue
      con = Faraday.new(url:, params:, headers:) do |f|
        f.use Faraday::Response::RaiseError
      end
      res = con.send(method) do |req|
        req.body = body.present? ? body : payload.to_json if body.present? || payload.present?
      end

      case content
      when :json
        res = JSON.parse(res.body.blank? ? "{}" : res.body, symbolize_names: true)
      when :text
        res = res.body
      end

      puts res if !quiet && res.present?
      res
    rescue Faraday::Error => error
      details = error_details(error)
      raise error if details.blank?

      raise ResponseError.new(
        "#{method.to_s.upcase} #{url} failed (#{error.response[:status]}): #{details}",
        status: error.response[:status],
      ), cause: nil
    end

    private

    def error_details(error)
      JSON.parse(error.response[:body].to_s)
        .fetch("errors", [])
        .flat_map { |item| nested_error_details(item) }
        .uniq
        .join("; ")
    rescue JSON::ParserError
      nil
    end

    def nested_error_details(value)
      return value.flat_map { |item| nested_error_details(item) } if value.is_a?(Array)
      return [] unless value.is_a?(Hash)

      [
        value["detail"] || value["title"],
        *value.values.flat_map { |item| nested_error_details(item) },
      ].compact
    end
  end
end
