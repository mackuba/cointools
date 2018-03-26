$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "cointools"

require 'json'
require 'webmock/rspec'

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
end

def json(hash)
  JSON.generate(hash)
end
