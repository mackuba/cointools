require_relative 'version'

require 'json'

module CoinTools
  class Cryptowatch
    BASE_URL = "https://api.cryptowat.ch"
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

    def get_price(exchange, market, time = nil)
      return get_current_price(exchange, market) if time.nil?

      (time <= Time.now) or raise InvalidDateException.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateException.new('Too early date was passed')

      unixtime = time.to_i
      url = URI("#{BASE_URL}/markets/#{exchange}/#{market}/ohlc?after=#{unixtime}&periods=300")

      response = make_request(url)

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

    def get_current_price(exchange, market)
      url = URI("#{BASE_URL}/markets/#{exchange}/#{market}/price")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        price = json['result']['price']

        return DataPoint.new(price, Time.now)
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
