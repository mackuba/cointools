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

    class Listing
      attr_reader :numeric_id, :name, :symbol, :text_id

      def initialize(json)
        [:id, :name, :symbol, :website_slug].each do |key|
          raise ArgumentError.new("Missing #{key} field") unless json[key.to_s]
        end

        @numeric_id = json['id']
        @name = json['name']
        @symbol = json['symbol']
        @text_id = json['website_slug']
      end
    end

    class CoinData < Listing
      attr_reader :last_updated, :usd_price, :btc_price, :converted_price, :rank, :market_cap

      def initialize(json, convert_to = nil)
        super(json)

        raise ArgumentError.new('Missing rank field') unless json['rank']
        raise ArgumentError.new('Invalid rank field') unless json['rank'].is_a?(Integer) && json['rank'] > 0
        @rank = json['rank']

        quotes = json['quotes']
        raise ArgumentError.new('Missing quotes field') unless quotes
        raise ArgumentError.new('Invalid quotes field') unless quotes.is_a?(Hash)

        usd_quote = quotes['USD']
        raise ArgumentError.new('Missing USD quote info') unless usd_quote
        raise ArgumentError.new('Invalid USD quote info') unless usd_quote.is_a?(Hash)

        @usd_price = usd_quote['price']&.to_f
        @market_cap = usd_quote['market_cap']&.to_f

        if convert_to
          converted_quote = quotes[convert_to.upcase]

          if converted_quote
            raise ArgumentError.new("Invalid #{convert_to.upcase} quote info") unless converted_quote.is_a?(Hash)
            @converted_price = converted_quote['price']&.to_f
          end
        else
          btc_quote = quotes['BTC']

          if btc_quote
            raise ArgumentError.new("Invalid BTC quote info") unless btc_quote.is_a?(Hash)
            @btc_price = btc_quote['price']&.to_f
          end
        end

        timestamp = json['last_updated']
        @last_updated = Time.at(timestamp) if timestamp
      end
    end

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
        raise JSONError.new(response) unless json.is_a?(Hash) && json['metadata']
        raise BadRequestError.new(response, json['metadata']['error']) if json['metadata']['error']
        raise JSONError.new(response) unless json['data'].is_a?(Array)

        @id_map = {}
        @symbol_map = {}

        begin
          json['data'].each do |record|
            listing = Listing.new(record)

            @id_map[listing.text_id] = listing
            @symbol_map[listing.symbol] = listing
          end
        rescue ArgumentError => e
          # TODO: JSONError vs. NoDataError? + error class docs
          raise JSONError.new(response, e.message)
        end

        json['data'].length
      when Net::HTTPClientError
        raise BadRequestError.new(response)
      else
        raise ServiceUnavailableError.new(response)
      end
    end

    def get_price(coin_name, convert_to: nil)
      raise InvalidSymbolError if coin_name.to_s.empty?

      validate_fiat_currency(convert_to) if convert_to

      listing = id_map[coin_name.to_s]
      raise InvalidSymbolError if listing.nil?

      get_price_for_listing(listing, convert_to: convert_to)
    end

    def get_price_by_symbol(coin_symbol, convert_to: nil)
      raise InvalidSymbolError if coin_symbol.to_s.empty?

      validate_fiat_currency(convert_to) if convert_to

      listing = symbol_map[coin_symbol.to_s]
      raise InvalidSymbolError if listing.nil?

      get_price_for_listing(listing, convert_to: convert_to)
    end

    def get_price_for_listing(listing, convert_to: nil)
      url = URI("#{BASE_URL}/v2/ticker/#{listing.numeric_id}/")

      if convert_to
        url.query = "convert=#{convert_to}"
      else
        url.query = "convert=BTC"
      end

      response = make_request(url)

      case response
      when Net::HTTPSuccess
        json = Utils.parse_json(response.body)
        raise JSONError.new(response) unless json.is_a?(Hash) && json['metadata']
        raise BadRequestError.new(response, json['metadata']['error']) if json['metadata']['error']

        record = json['data']
        raise JSONError.new(response) unless record.is_a?(Hash)

        begin
          return CoinData.new(record, convert_to)
        rescue ArgumentError => e
          raise JSONError.new(response, e.message)
        end
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
        validate_fiat_currency(convert_to)
        url.query += "&convert=#{convert_to}"
      else
        url.query += "&convert=BTC"
      end

      start = 0
      coins = []

      loop do
        page_url = url.clone
        page_url.query += "&start=#{coins.length}"
        response = make_request(page_url)

        case response
        when Net::HTTPSuccess
          json = Utils.parse_json(response.body)
          raise JSONError.new(response) unless json.is_a?(Hash) && json['data'] && json['metadata']
          raise NoDataError.new(response, json['metadata']['error']) if json['metadata']['error']
          raise JSONError.new(response) unless json['data'].is_a?(Array)

          begin
            new_batch = json['data'].map { |record| CoinData.new(record, convert_to) }
          rescue ArgumentError => e
            raise JSONError.new(response, e.message)
          end

          coins.concat(new_batch)
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
