require_relative 'version'

require 'json'
require 'net/http'
require 'uri'

module CoinTools
  class CoinMarketCap
    BASE_URL = "https://api.coinmarketcap.com"
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

    class NoDataException < StandardError
    end

    class InvalidDateException < StandardError
    end

    def get_price(coin_name)
      url = URI("#{BASE_URL}/v1/ticker/#{coin_name}/")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        record = json[0]

        price = record['price_usd'].to_f
        timestamp = Time.at(record['last_updated'].to_i)

        return DataPoint.new(price, timestamp)
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise Exception.new(response)
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
