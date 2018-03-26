require_relative 'version'

require 'json'
require 'net/http'
require 'uri'

module CoinTools
  class BitBay
    BASE_URL = "https://bitbay.net/API/Public"
    USER_AGENT = "cointools/#{CoinTools::VERSION}"

    DataPoint = Struct.new(:price, :time)

    class InvalidResponseException < StandardError
      attr_reader :response

      def initialize(response)
        super("#{response.code} #{response.message}")
        @response = response
      end
    end

    class BadRequestException < InvalidResponseException
    end

    class ErrorResponseException < StandardError
    end

    def get_price(market)
      url = URI("#{BASE_URL}/#{market}/ticker.json")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)

        if json['code']
          raise ErrorResponseException.new("#{json['code']} #{json['message']}")
        end

        price = json['last']

        return DataPoint.new(price, nil)
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise InvalidResponseException.new(response)
      end
    end

    private

    def make_request(url)
      Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new(url)
        request['User-Agent'] = USER_AGENT

        http.request(request)
      end
    end
  end
end
