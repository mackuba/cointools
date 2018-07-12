require 'net/http'
require 'uri'

require_relative 'version'

module CoinTools
  module Request
    USER_AGENT = "cointools/#{CoinTools::VERSION}"

    def self.get(url)
      url = URI(url) if url.is_a?(String)

      Net::HTTP.start(url.host, url.port, use_ssl: true) do |http|
        request = Net::HTTP::Get.new(url)
        request['User-Agent'] = USER_AGENT

        http.request(request)
      end
    end
  end
end
