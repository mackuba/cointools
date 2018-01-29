# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'cointools/version'

Gem::Specification.new do |spec|
  spec.name          = "cointools"
  spec.version       = CoinTools::VERSION
  spec.authors       = ["Kuba Suder"]
  spec.email         = ["jakub.suder@gmail.com"]

  spec.summary       = "A collection of scripts for checking cryptocurrency prices."
  spec.homepage      = "https://github.com/mackuba/cointools"
  spec.license       = "Nonstandard"

  spec.files         = ['CHANGELOG.md', 'README.md', 'VSPL-LICENSE.txt'] + Dir['lib/**/*']

  spec.bindir        = "bin"
  spec.executables   = Dir['bin/*'].map { |f| File.basename(f) } - ['console', 'setup']
end
