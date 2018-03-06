# Cointools

This is a collection of Ruby scripts and library classes that let you check cryptocurrency prices on various services.

## Installation

To use the scripts from the command line, install the gem:

```
gem install cointools
```

To use the code as a library, add it to your Gemfile:

```ruby
gem 'cointools'
```

## [Cryptowatch](https://cryptowat.ch)

To check past price of a given coin on a chosen exchange, pass the exchange and market name and a properly formatted timestamp:

```
cryptowatch bitfinex btcusd "2017-12-17 13:00"
```

To check the current price, skip the timestamp:

```
cryptowatch bitfinex btcusd
```

You can fetch a list of available exchanges and markets using these commands:

```
cryptowatch --list-exchanges
cryptowatch --list-markets bithumb
```

In code:

```ruby
require 'cointools'  # or 'cointools/cryptowatch'
cryptowatch = CoinTools::Cryptowatch.new

exchange = cryptowatch.exchanges.first

list = cryptowatch.get_markets(exchange)
market = list.select { |x| x =~ /ltc/ && x !~ /btc/ }.first.upcase

result = cryptowatch.get_price(exchange, market, Time.now - 86400)
puts "#{market} yesterday: #{result.price}"

result = cryptowatch.get_current_price(exchange, market)
puts "#{market} today: #{result.price}"
```

The result object contains the requested price and (for historical prices) the actual timestamp of the found price, which might slightly differ from the timestamp passed in the argument (the earlier the date, the less precise the result).


## [CoinMarketCap](https://coinmarketcap.com)

CoinMarketCap's API only returns current coin prices. To look up a coin's price, you need to pass its name as used on CoinMarketCap:

```
coinmcap power-ledger
```

Alternatively, you can pass the cryptocurrency's symbol using the `-s` or `--symbol` parameter:

```
coinmcap -s powr
```

However, this operation needs to download a complete ticker for all currencies and scan through the list, so it's recommended to use the name as in the example above.

You can also use the `-b` or `--btc-price` flag to request a price in BTC instead of USD:

```
coinmcap power-ledger -b
```

Or you can request the price in one of the ~30 other supported fiat currencies with `-f` or `--fiat-currency`:

```
coinmcap request-network -fEUR
```

You can print a list of supported fiat currencies with `coinmcap --list-fiat-currencies`.

Same things in code:

```ruby
require 'cointools'  # or 'cointools/coinmarketcap'
cmc = CoinTools::CoinMarketCap.new

p CoinTools::CoinMarketCap::FIAT_CURRENCIES

ltc = cryptowatch.get_price('litecoin')
puts "LTC: #{ltc.usd_price} USD / #{ltc.btc_price} BTC"

xmr = cryptowatch.get_price_by_symbol('xmr')
puts "XMR: #{xmr.usd_price} USD / #{xmr.btc_price} BTC"

eth = cryptowatch.get_price('ethereum', convert_to: 'EUR')
puts "ETH: #{eth.converted_price} EUR"
```


## Credits & contributing

Copyright © 2018 [Kuba Suder](https://mackuba.eu). Licensed under [MIT License](http://opensource.org/licenses/MIT).

If you'd like to help me extend the scripts with some additional features or add support for new services, [send me a pull request](https://github.com/mackuba/cointools/pulls).
