require_relative 'errors'

require 'json'
require 'time'

module CoinTools
  module Utils
    class << self
      def parse_json(text)
        JSON.parse(text, quirks_mode: true)
      end

      def parse_time(text)
        Time.parse(text)
      rescue ArgumentError => e
        raise InvalidDateError.new(e.message)
      end
    end
  end
end
