require_relative 'version'

require 'json'
require 'net/http'
require 'uri'

module CoinTools
  class CoinCap
    BASE_URL = "https://coincap.io"
    USER_AGENT = "cointools/#{CoinTools::VERSION}"

    DataPoint = Struct.new(:time, :usd_price, :eur_price, :btc_price)

    PERIODS = [1, 7, 30, 90, 180, 365]

    class InvalidResponseException < StandardError
      attr_reader :response

      def initialize(response)
        super("#{response.code} #{response.message}")
        @response = response
      end
    end

    class BadRequestException < InvalidResponseException
    end

    class InvalidDateException < StandardError
    end

    def get_price(symbol, time = nil)
      return get_current_price(symbol) if time.nil?

      (time <= Time.now) or raise InvalidDateException.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateException.new('Too early date was passed')

      period = period_for_time(time)

      if period
        url = URI("#{BASE_URL}/history/#{period}day/#{symbol.upcase}")
      else
        url = URI("#{BASE_URL}/history/#{symbol.upcase}")
      end

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        data = json['price']
        unixtime = time.to_i

        timestamp, price = best_matching_record(data, unixtime)
        actual_time = Time.at(timestamp / 1000)

        return DataPoint.new(actual_time, price, nil, nil)
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise InvalidResponseException.new(response)
      end
    end

    def get_current_price(symbol)
      url = URI("#{BASE_URL}/page/#{symbol.upcase}")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)

        usd_price = json['price_usd']
        eur_price = json['price_eur']
        btc_price = json['price_btc']

        return DataPoint.new(nil, usd_price, eur_price, btc_price)
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

    def best_matching_record(data, unixtime)
      millitime = unixtime * 1000
      data.sort_by { |record| (record[0] - millitime).abs }.first
    end

    def period_for_time(time)
      now = Time.now

      PERIODS.map { |p| [p, now - p * 86400 + 7200] }.detect { |p, t| t < time }&.first
    end
  end
end
