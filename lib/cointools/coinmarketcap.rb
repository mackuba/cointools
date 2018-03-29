require_relative 'version'

require 'json'
require 'net/http'
require 'uri'

module CoinTools
  class CoinMarketCap
    BASE_URL = "https://api.coinmarketcap.com"
    USER_AGENT = "cointools/#{CoinTools::VERSION}"

    FIAT_CURRENCIES = [
      'AUD', 'BRL', 'CAD', 'CHF', 'CLP', 'CNY', 'CZK', 'DKK', 'EUR', 'GBP',
      'HKD', 'HUF', 'IDR', 'ILS', 'INR', 'JPY', 'KRW', 'MXN', 'MYR', 'NOK',
      'NZD', 'PHP', 'PKR', 'PLN', 'RUB', 'SEK', 'SGD', 'THB', 'TRY', 'TWD',
      'ZAR'
    ]

    class DataPoint
      attr_reader :time, :usd_price, :btc_price, :converted_price

      def initialize(time, usd_price, btc_price, converted_price = nil)
        @time = time
        @usd_price = usd_price
        @btc_price = btc_price
        @converted_price = converted_price
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

    class InvalidFiatCurrencyException < StandardError
    end

    class InvalidDateException < StandardError
    end

    def get_price(coin_name, convert_to: nil)
      url = URI("#{BASE_URL}/v1/ticker/#{coin_name}/")

      if convert_to
        validate_fiat_currency(convert_to)
        url += "?convert=#{convert_to}"
      end

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        record = json[0]

        usd_price = record['price_usd']&.to_f
        btc_price = record['price_btc']&.to_f
        timestamp = Time.at(record['last_updated'].to_i)

        if convert_to
          converted_price = record["price_#{convert_to.downcase}"]&.to_f
          raise NoDataException.new('Conversion to chosen fiat currency failed') if converted_price.nil?
        end

        return DataPoint.new(timestamp, usd_price, btc_price, converted_price)
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise InvalidResponseException.new(response)
      end
    end

    def get_price_by_symbol(coin_symbol, convert_to: nil)
      url = URI("#{BASE_URL}/v1/ticker/?limit=0")
      symbol = coin_symbol.downcase

      if convert_to
        validate_fiat_currency(convert_to)
        url.query += "&convert=#{convert_to}"
      end

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        record = json.detect { |r| r['symbol'].downcase == symbol }
        raise NoDataException.new('No coin found with given symbol') if record.nil?

        usd_price = record['price_usd']&.to_f
        btc_price = record['price_btc']&.to_f
        timestamp = Time.at(record['last_updated'].to_i)

        if convert_to
          converted_price = record["price_#{convert_to.downcase}"]&.to_f
          raise NoDataException.new('Conversion to chosen fiat currency failed') if converted_price.nil?
        end

        return DataPoint.new(timestamp, usd_price, btc_price, converted_price)
      when Net::HTTPBadRequest
        raise BadRequestException.new(response)
      else
        raise Exception.new(response)
      end
    end


    private

    def validate_fiat_currency(fiat_currency)
      unless FIAT_CURRENCIES.include?(fiat_currency.upcase)
        raise InvalidFiatCurrencyException
      end
    end

    def make_request(url)
      Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new(url)
        request['User-Agent'] = USER_AGENT

        http.request(request)
      end
    end
  end
end
