require_relative 'errors'
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


    def get_price(symbol, time = nil)
      raise InvalidSymbolError if symbol.to_s.empty?

      return get_current_price(symbol) if time.nil?

      (time <= Time.now) or raise InvalidDateError.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateError.new('Too early date was passed')

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
        raise UnknownCoinError.new(response) if json.nil? || json.empty?

        data = json['price']
        raise JSONError.new(response) unless data.is_a?(Array)

        unixtime = time.to_i
        timestamp, price = best_matching_record(data, unixtime)
        raise NoDataError.new(response) if timestamp.nil? || price.nil?

        actual_time = Time.at(timestamp / 1000)

        return DataPoint.new(actual_time, price, nil, nil)
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_current_price(symbol)
      raise InvalidSymbolError if symbol.to_s.empty?

      url = URI("#{BASE_URL}/page/#{symbol.upcase}")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        raise UnknownCoinError.new(response) if json.nil? || json.empty?

        usd_price = json['price_usd']
        eur_price = json['price_eur']
        btc_price = json['price_btc']

        if usd_price || eur_price || btc_price
          return DataPoint.new(nil, usd_price, eur_price, btc_price)
        else
          raise NoDataError.new(response)
        end
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
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
