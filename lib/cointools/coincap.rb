require_relative 'base_struct'
require_relative 'errors'
require_relative 'request'
require_relative 'utils'

require 'net/http'
require 'uri'

module CoinTools
  class CoinCap
    BASE_URL = "https://coincap.io"
    PERIODS = [1, 7, 30, 90, 180, 365]

    DataPoint = BaseStruct.make(:time, :usd_price, :eur_price, :btc_price)


    def get_price(symbol, time = nil)
      raise InvalidSymbolError if symbol.to_s.empty?

      if time.nil?
        return get_current_price(symbol)
      elsif time.is_a?(String)
        time = Utils.parse_time(time)
      end

      (time <= Time.now) or raise InvalidDateError.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateError.new('Too early date was passed')

      period = period_for_time(time)

      if period
        url = URI("#{BASE_URL}/history/#{period}day/#{symbol.upcase}")
      else
        url = URI("#{BASE_URL}/history/#{symbol.upcase}")
      end

      response = Request.get(url)

      case response
      when Net::HTTPSuccess
        json = Utils.parse_json(response.body)
        raise UnknownCoinError.new(response) if json.nil? || json.empty?
        raise JSONError.new(response) unless json.is_a?(Hash)

        data = json['price']
        raise JSONError.new(response) unless data.is_a?(Array)

        unixtime = time.to_i
        timestamp, price = best_matching_record(data, unixtime)
        raise NoDataError.new(response) if timestamp.nil? || price.nil?

        actual_time = Time.at(timestamp / 1000)

        return DataPoint.new(time: actual_time, usd_price: price, eur_price: nil, btc_price: nil)
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_current_price(symbol)
      raise InvalidSymbolError if symbol.to_s.empty?

      url = URI("#{BASE_URL}/page/#{symbol.upcase}")

      response = Request.get(url)

      case response
      when Net::HTTPSuccess
        json = Utils.parse_json(response.body)
        raise UnknownCoinError.new(response) if json.nil? || json.empty?
        raise JSONError.new(response) unless json.is_a?(Hash)

        usd_price = json['price_usd']
        eur_price = json['price_eur']
        btc_price = json['price_btc']

        if usd_price || eur_price || btc_price
          return DataPoint.new(time: nil, usd_price: usd_price, eur_price: eur_price, btc_price: btc_price)
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
