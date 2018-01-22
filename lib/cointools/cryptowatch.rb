require_relative 'version'

require 'json'
require 'open-uri'

module CoinTools
  class Cryptowatch
    BASE_URL = "https://api.cryptowat.ch/markets"
    HEADERS = { 'User-Agent' => "cointools #{CoinTools::VERSION}" }

    class DataPoint
      attr_reader :price, :time

      def initialize(price, time)
        @price = price
        @time = time
      end
    end

    def get_price(exchange, market, time = nil)
      unixtime = time.to_i
      data = open("#{BASE_URL}/#{exchange}/#{market}/ohlc?after=#{unixtime}&periods=300", HEADERS).read
      json = JSON.load(data)
      timestamp, o, h, l, c, volume = json['result']['300'].detect { |r| r[0] >= unixtime }
      actual_time = Time.at(timestamp)

      return DataPoint.new(o, actual_time)
    # rescue OpenURI::HTTPError => e
      # puts "Connection error or coin not found: #{e}"
    end
  end
end
