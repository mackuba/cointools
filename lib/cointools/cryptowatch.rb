require_relative 'base_struct'
require_relative 'errors'
require_relative 'utils'
require_relative 'version'

require 'json'
require 'net/http'
require 'uri'

module CoinTools
  class Cryptowatch
    BASE_URL = "https://api.cryptowat.ch"
    USER_AGENT = "cointools/#{CoinTools::VERSION}"

    DataPoint = BaseStruct.make(:price, :time, :api_time_spent, :api_time_remaining)

    # we expect this many days worth of data for a given period precision (in seconds); NOT guaranteed by the API
    DAYS_FOR_PERIODS = {
      60 => 3, 180 => 10, 300 => 15, 900 => 2 * 30, 1800 => 4 * 30, 3600 => 8 * 30,
      7200 => 365, 14400 => 1.5 * 365, 21600 => 2 * 365, 43200 => 3 * 365, 86400 => 4 * 365
    }

    def exchanges
      @exchanges ||= get_exchanges
    end

    def get_markets(exchange)
      raise InvalidExchangeError if exchange.to_s.empty?

      url = URI("#{BASE_URL}/markets/#{exchange}")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash) && json['result'].is_a?(Array)

        return json['result'].select { |m| m['active'] == true }.map { |m| m['pair'] }.sort
      when Net::HTTPNotFound
        raise UnknownExchangeError.new(response)
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_price(exchange, market, time = nil)
      raise InvalidExchangeError if exchange.to_s.empty?
      raise InvalidSymbolError if market.to_s.empty?

      if time.nil?
        return get_current_price(exchange, market)
      elsif time.is_a?(String)
        time = Utils.parse_time(time)
      end

      (time <= Time.now) or raise InvalidDateError.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateError.new('Too early date was passed')

      unixtime = time.to_i
      current_time = Time.now.to_i
      url = URI("#{BASE_URL}/markets/#{exchange}/#{market}/ohlc?after=#{unixtime}")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash)

        data = json['result']
        allowance = json['allowance']
        raise JSONError.new(response) unless data.is_a?(Hash) && allowance.is_a?(Hash)

        timestamp, o, h, l, c, volume = best_matching_record(data, unixtime, current_time)
        raise NoDataError.new(response, 'No price data returned') unless timestamp && o

        actual_time = Time.at(timestamp)

        return DataPoint.new(
          price: o,
          time: actual_time,
          api_time_spent: allowance['cost'],
          api_time_remaining: allowance['remaining']
        )
      when Net::HTTPNotFound
        raise UnknownCoinError.new(response)
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_current_price(exchange, market)
      raise InvalidExchangeError if exchange.to_s.empty?
      raise InvalidSymbolError if market.to_s.empty?

      url = URI("#{BASE_URL}/markets/#{exchange}/#{market}/price")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash)

        data = json['result']
        allowance = json['allowance']
        raise JSONError.new(response) unless data.is_a?(Hash) && allowance.is_a?(Hash)

        price = data['price']
        raise NoDataError.new(response) unless price

        return DataPoint.new(
          price: price,
          time: nil,
          api_time_spent: allowance['cost'],
          api_time_remaining: allowance['remaining']
        )
      when Net::HTTPNotFound
        raise UnknownCoinError.new(response)
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_price_fast(exchange, market, time = nil)
      raise InvalidExchangeError if exchange.to_s.empty?
      raise InvalidSymbolError if market.to_s.empty?

      if time.nil?
        return get_current_price(exchange, market)
      elsif time.is_a?(String)
        time = Utils.parse_time(time)
      end

      (time <= Time.now) or raise InvalidDateError.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateError.new('Too early date was passed')

      period = precision_for_time(time)

      if period.nil?
        return get_price(exchange, market, time)
      end

      unixtime = time.to_i
      current_time = Time.now.to_i
      url = URI("#{BASE_URL}/markets/#{exchange}/#{market}/ohlc?after=#{unixtime}&periods=#{period}")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash)

        data = json['result']
        allowance = json['allowance']
        raise JSONError.new(response) unless data.is_a?(Hash) && allowance.is_a?(Hash)

        timestamp, o, h, l, c, volume = best_matching_record(data, unixtime, current_time)
        raise NoDataError.new(response, 'No price data returned') unless timestamp && o

        actual_time = Time.at(timestamp)

        return DataPoint.new(
          price: o,
          time: actual_time,
          api_time_spent: allowance['cost'],
          api_time_remaining: allowance['remaining']
        )
      when Net::HTTPNotFound
        raise UnknownCoinError.new(response)
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

    def best_matching_record(data, unixtime, request_time)
      candidates = []

      data.keys.sort_by { |k| k.to_i }.each do |k|
        records = data[k] || []
        previous = nil

        records.each do |record|
          timestamp, o, h, l, c, volume = record

          if timestamp >= unixtime
            candidates.push(record) unless timestamp > request_time
            break
          else
            previous = record
          end
        end

        candidates.push(previous) if previous
      end

      candidates.sort_by { |record| (record[0] - unixtime).abs }.first
    end

    def precision_for_time(time)
      now = Time.now

      DAYS_FOR_PERIODS.keys.sort.each do |period|
        days = DAYS_FOR_PERIODS[period]
        earliest_date = now - days * 86400

        if earliest_date < time
          return period
        end
      end

      nil
    end

    def get_exchanges
      url = URI("#{BASE_URL}/exchanges")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash) && json['result'].is_a?(Array)

        return json['result'].select { |e| e['active'] == true }.map { |e| e['symbol'] }.sort
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end
  end
end
