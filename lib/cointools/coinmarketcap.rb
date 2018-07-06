require_relative 'base_struct'
require_relative 'errors'
require_relative 'utils'
require_relative 'version'

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

    Listing = BaseStruct.make(:numeric_id, :name, :symbol, :text_id)
    DataPoint = BaseStruct.make(:time, :usd_price, :btc_price, :converted_price)

    def symbol_map
      load_listings if @symbol_map.nil?
      @symbol_map
    end

    def id_map
      load_listings if @id_map.nil?
      @id_map
    end

    def load_listings
      url = URI("#{BASE_URL}/v2/listings/")

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = Utils.parse_json(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash) && json['data'] && json['metadata']
        raise BadRequestError.new(response, json['metadata']['error']) if json['metadata']['error']
        raise JSONError.new(response) unless json['data'].is_a?(Array)

        @id_map = {}
        @symbol_map = {}

        json['data'].each do |record|
          listing = Listing.new(
            numeric_id: record['id'], 
            name: record['name'],
            symbol: record['symbol'],
            text_id: record['website_slug']
          )

          # TODO: JSONError vs. NoDataError? + error class docs
          unless listing.numeric_id && listing.name && listing.symbol && listing.text_id
            raise JSONError.new(response, "Missing field in record: #{record}")
          end

          @id_map[listing.text_id] = listing
          @symbol_map[listing.symbol] = listing
        end
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_price(coin_name, convert_to: nil)
      raise InvalidSymbolError if coin_name.to_s.empty?

      listing = id_map[coin_name.to_s]
      raise InvalidSymbolError if listing.nil?

      get_price_for_listing(listing, convert_to: convert_to)
    end

    def get_price_by_symbol(coin_symbol, convert_to: nil)
      raise InvalidSymbolError if coin_symbol.to_s.empty?

      listing = symbol_map[coin_symbol.to_s]
      raise InvalidSymbolError if listing.nil?

      get_price_for_listing(listing, convert_to: convert_to)
    end

    def get_price_for_listing(listing, convert_to: nil)
      url = URI("#{BASE_URL}/v2/ticker/#{listing.numeric_id}/")

      if convert_to
        currency = convert_to.upcase
        validate_fiat_currency(currency)
        url.query = "convert=#{currency}"
      else
        url.query = "convert=BTC"
      end

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = Utils.parse_json(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash) && json['data'] && json['metadata']
        raise BadRequestError.new(response, json['metadata']['error']) if json['metadata']['error']

        record = json['data']
        raise JSONError.new(response) unless record.is_a?(Hash)

        quotes = record['quotes']
        raise JSONError.new(response, 'Missing quotes field') unless quotes

        usd_price = quotes['USD'] && quotes['USD']['price']&.to_f
        btc_price = quotes['BTC'] && quotes['BTC']['price']&.to_f
        timestamp = Time.at(record['last_updated'].to_i)

        if currency
          converted_price = quotes[currency] && quotes[currency]['price']&.to_f
        end

        return DataPoint.new(
          time: timestamp,
          usd_price: usd_price,
          btc_price: btc_price,
          converted_price: converted_price
        )
      when Net::HTTPNotFound
        raise UnknownCoinError.new(response)
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
          json = Utils.parse_json(response.body)
          raise JSONError.new(response) unless json.is_a?(Hash) && json['data'] && json['metadata']
          raise NoDataError.new(response, json['metadata']['error']) if json['metadata']['error']
          raise JSONError.new(response) unless json['data'].is_a?(Array)

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

            coins[id] = DataPoint.new(
              time: timestamp,
              usd_price: usd_price,
              btc_price: btc_price,
              converted_price: converted_price
            )
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
