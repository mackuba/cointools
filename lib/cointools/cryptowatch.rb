require_relative 'version'

require 'json'

module CoinTools
  class Cryptowatch
    BASE_URL = "https://api.cryptowat.ch/markets"
    USER_AGENT = "cointools/#{CoinTools::VERSION}"

    class DataPoint
      attr_reader :price, :time

      def initialize(price, time)
        @price = price
        @time = time
      end
    end

    class Exception < StandardError
      attr_reader :response

      def initialize(response)
        super("#{response.code} #{response.message}")
        @response = response
      end
    end

    def get_price(exchange, market, time = nil)
      unixtime = time.to_i
      url = URI("#{BASE_URL}/#{exchange}/#{market}/ohlc?after=#{unixtime}&periods=300")

      response = Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new(url)
        request['User-Agent'] = USER_AGENT

        http.request(request)
      end

      case response
      when Net::HTTPSuccess
        json = JSON.load(response.body)
        timestamp, o, h, l, c, volume = json['result']['300'].detect { |r| r[0] >= unixtime }
        actual_time = Time.at(timestamp)
        return DataPoint.new(o, actual_time)
      else
        raise Exception.new(response)
      end

    # rescue OpenURI::HTTPError => e
      # puts "Connection error or coin not found: #{e}"
    end
  end
end
