require_relative 'errors'

require 'time'

module CoinTools
  module Utils
    class << self
      def parse_time(text)
        Time.parse(text)
      rescue ArgumentError => e
        raise InvalidDateError.new(e.message)
      end
    end
  end
end
