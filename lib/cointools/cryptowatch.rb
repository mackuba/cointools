require_relative 'version'

require 'json'
require 'net/http'
require 'uri'

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

    def exchanges
      @exchanges ||= get_exchanges
    end

    def get_markets(exchange)
      url = URI("#{BASE_URL}/markets/#{exchange}")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        return json['result'].select { |m| m['active'] == true }.map { |m| m['pair'] }.sort
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise InvalidResponseException.new(response)
      end
    end

    def get_price(exchange, market, time = nil)
      return get_current_price(exchange, market) if time.nil?

      (time <= Time.now) or raise InvalidDateException.new('Future date was passed')
      (time.year >= 2009) or raise InvalidDateException.new('Too early date was passed')

      unixtime = time.to_i
      current_time = Time.now.to_i
      url = URI("#{BASE_URL}/markets/#{exchange}/#{market}/ohlc?after=#{unixtime}")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        data = json['result']

        timestamp, o, h, l, c, volume = best_matching_record(data, unixtime, current_time)
        raise NoDataException.new('No data found for a given time') if timestamp.nil?

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

        return DataPoint.new(price, nil)
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

    def best_matching_record(data, unixtime, request_time)
      candidates = []

      data.keys.sort_by { |k| k.to_i }.each do |k|
        records = data[k]
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

    def get_exchanges
      url = URI("#{BASE_URL}/exchanges")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        return json['result'].select { |e| e['active'] == true }.map { |e| e['symbol'] }.sort
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise Exception.new(response)
      end
    end
  end
end
