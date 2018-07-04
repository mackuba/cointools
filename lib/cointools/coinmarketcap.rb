require_relative 'errors'
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

    def get_price(coin_name, convert_to: nil)
      raise InvalidSymbolError if coin_name.to_s.empty?

      url = URI("#{BASE_URL}/v1/ticker/#{coin_name}/")

      if convert_to
        validate_fiat_currency(convert_to)
        url += "?convert=#{convert_to}"
      end

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        raise JSONError.new(response) unless json.is_a?(Array)

        record = json[0]

        usd_price = record['price_usd']&.to_f
        btc_price = record['price_btc']&.to_f
        timestamp = Time.at(record['last_updated'].to_i)

        raise NoDataError.new(response) unless usd_price && btc_price && record['last_updated']

        if convert_to
          converted_price = record["price_#{convert_to.downcase}"]&.to_f
          raise NoDataError.new(response, 'Conversion to chosen fiat currency failed') if converted_price.nil?
        end

        return DataPoint.new(timestamp, usd_price, btc_price, converted_price)
      when Net::HTTPNotFound
        raise UnknownCoinError.new(response)
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_price_by_symbol(coin_symbol, convert_to: nil)
      raise InvalidSymbolError if coin_symbol.to_s.empty?

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
        raise JSONError.new(response) unless json.is_a?(Array)

        record = json.detect { |r| r['symbol'].downcase == symbol }
        raise UnknownCoinError.new(response) if record.nil?

        usd_price = record['price_usd']&.to_f
        btc_price = record['price_btc']&.to_f
        timestamp = Time.at(record['last_updated'].to_i)

        raise NoDataError.new(response) unless usd_price && btc_price && timestamp

        if convert_to
          converted_price = record["price_#{convert_to.downcase}"]&.to_f
          raise NoDataError.new(response, 'Conversion to chosen fiat currency failed') if converted_price.nil?
        end

        return DataPoint.new(timestamp, usd_price, btc_price, converted_price)
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_all_prices(convert_to: nil)
      url = URI("#{BASE_URL}/v2/ticker/?structure=array&sort=id&limit=100")

      if convert_to
        currency = convert_to.upcase
        validate_fiat_currency(convert_to)
        url.query += "&convert=#{currency}"
      else
        url.query += "&convert=BTC"
      end

      start = 0
      coins = {}

      loop do
        page_url = url.clone
        page_url.query += "&start=#{start}"
        response = make_request(page_url)

        case response
        when Net::HTTPSuccess
          json = JSON.load(response.body)
          raise JSONError.new(response) unless json.is_a?(Hash) && json['data'] && json['metadata']
          raise NoDataError.new(response, json['metadata']['error']) if json['metadata']['error']

          json['data'].each do |record|
            quotes = record['quotes']
            raise JSONError.new(response, 'Missing quotes field') unless quotes

            id = record['website_slug']
            raise JSONError.new(response, 'Missing id field') unless id

            usd_price = quotes['USD'] && quotes['USD']['price']&.to_f
            btc_price = quotes['BTC'] && quotes['BTC']['price']&.to_f
            timestamp = Time.at(record['last_updated'].to_i)

            if currency
              converted_price = quotes[currency] && quotes[currency]['price']&.to_f
            end

            coins[id] = DataPoint.new(timestamp, usd_price, btc_price, converted_price)
          end

          start += json['data'].length
        when Net::HTTPNotFound
          break
        when Net::HTTPClientError
          raise BadRequestError.new(response)
        else
          raise ServiceUnavailableError.new(response)
        end
      end

      coins
    end


    private

    def validate_fiat_currency(fiat_currency)
      unless FIAT_CURRENCIES.include?(fiat_currency.upcase)
        raise InvalidFiatCurrencyError
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
