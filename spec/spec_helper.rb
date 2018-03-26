$LOAD_PATH.unshift File.expand_path("../../lib", __FILE__)
require "cointools"

RSpec.configure do |config|
  config.expect_with(:rspec) { |c| c.syntax = :should }
end
