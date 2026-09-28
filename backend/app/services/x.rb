class X
  class << self
    def prod
      Rails.env.production?
    end

    def prod?
      prod
    end

    def dev
      Rails.env.development? && !prod?
    end

    def dev?
      dev
    end

    def test
      Rails.env.test?
    end

    def test?
      test
    end

    def host
      dev? ? ENV.fetch("TUNNEL_URL", Settings.development_url) : "https://#{Settings.all.fetch(:domain)}"
    end

    def wait(min = 0.5, max = 3.0)
      sleep(rand(min.to_f..max.to_f))
      nil
    end

    def timeout(max = 1.hour)
      Timeout.timeout(max.to_i) do
        yield
      end
    end

    def tryn(n = 3, sleep: 1.5)
      error = nil

      loop do
        n -= 1
        begin
          return yield(n)
        rescue StandardError => e
          error = e
        end

        break if n <= 0

        wait(sleep - 0.5, sleep + 0.5)
      end

      raise error if error
    end

    def recursive_deep_symbolize_keys(maybe)
      return maybe.deep_symbolize_keys if maybe.respond_to?(:deep_symbolize_keys)
      return maybe.map { |i| recursive_deep_symbolize_keys(i) } if maybe.respond_to?(:each)

      maybe
    end

    def recursive_open_struct(object)
      case object
      when Hash
        hash = {}; object.each { |k, v| hash[k] = recursive_open_struct(v) }
        OpenStruct.new(hash)
      when Array
        object.map { |e| recursive_open_struct(e) }
      else
        object
      end
    end
  end
end
