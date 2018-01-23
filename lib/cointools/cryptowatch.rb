require_relative 'version'

require 'json'

module CoinTools
  class Cryptowatch
    BASE_URL = "https://api.cryptowat.ch/markets"
    USER_AGENT = "cointools/#{CoinTools::VERSION}"

    class DataPoint
      attr_reader :price, :time

      def initialize(price, time)
        @price = price
        @time = time
      end
    end

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

    def get_price(exchange, market, time = nil)
      (time <= Time.now) or raise InvalidDateException.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateException.new('Too early date was passed')

      unixtime = time.to_i
      url = URI("#{BASE_URL}/#{exchange}/#{market}/ohlc?after=#{unixtime}&periods=300")

      response = Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new(url)
        request['User-Agent'] = USER_AGENT

        http.request(request)
      end

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        records = json['result']['300']
        raise NoDataException.new('No data found for a given time') if records.nil?

        timestamp, o, h, l, c, volume = records.detect { |r| r[0] >= unixtime }
        actual_time = Time.at(timestamp)
        return DataPoint.new(o, actual_time)
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise Exception.new(response)
      end
    end
  end
end
