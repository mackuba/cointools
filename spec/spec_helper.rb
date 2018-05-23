$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "cointools"

require 'json'
require 'webmock/rspec'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
  config.mock_with(:rspec) { |m| m.syntax = :should }
end

def json(hash)
  JSON.generate(hash)
end

def user_agent_header
  { 'User-Agent' => "cointools/#{CoinTools::VERSION}" }
end
