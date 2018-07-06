# CoinTools

This is a collection of Ruby scripts and library classes that let you check cryptocurrency prices on various services.

[![Gem Version](https://badge.fury.io/rb/cointools.svg)](https://badge.fury.io/rb/cointools) [![Build Status](https://travis-ci.org/mackuba/cointools.svg?branch=master)](https://travis-ci.org/mackuba/cointools)


## Installation

CoinTools requires Ruby version 2.3 or newer.

To use the scripts from the command line, install the gem (depending on your configuration, you might need to add `sudo`):

```
gem install cointools
```

To use the code as a library, add it to your Gemfile:

```ruby
gem 'cointools'
```

## Cryptowatch

[Cryptowat.ch](https://cryptowat.ch) is a coin charts site owned by Kraken which tracks historical cryptocurrency prices directly on many exchanges. It provides data from specific markets on specific exchanges, but no general rankings or average market prices.

To check past price of a given coin on a chosen exchange, pass the exchange and market name and a properly formatted timestamp:

```
cryptowatch bitfinex btcusd "2017-12-17 13:00"
```

To check the current price, skip the timestamp:

```
cryptowatch bitfinex btcusd
```

By default the price is printed in a verbose format that includes the requested market name and the time of the returned price. Add a `-q/--quiet` option to only print the price as a single number (e.g. to pass it further to another script).

You can fetch a list of available exchanges and markets using these commands:

```
cryptowatch --exchanges
cryptowatch --markets bithumb
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

The API is rate limited to 8 seconds of CPU time per hour - you can check the `api_time_spent` and `api_time_remaining` properties of the result object to see how much time allowance you have left.

If you need to do a large amount of lookups in a short period of time, try the alternative `#get_price_fast` method (or `-f` option on the command line). This method tries to guess which data set is the most appropriate for a given point in the past and requests only that set instead of all of them, which should use significantly less API time allowance. This however relies on an undocumented API behavior, so it's not guaranteed to return data and keep working in the future.


## CoinMarketCap

[CoinMarketCap](https://coinmarketcap.com) is by far the most popular site for checking coin rankings and BTC/USD prices for all coins available on the market. The API however only returns current average coin prices.

To look up a coin's price, you need to pass its name as used on CoinMarketCap:

```
cmcap power-ledger
```

Alternatively, you can pass the cryptocurrency's symbol using the `-s` or `--symbol` parameter:

```
cmcap -s powr
```

However, this operation needs to download a complete ticker for all currencies and scan through the list, so it's recommended to use the name as in the example above.

By default the price is printed in a verbose format that includes the requested coin symbol and the time of the returned price. Add a `-q/--quiet` option to only print the price as a single number (e.g. to pass it further to another script).

You can also use the `-b` or `--btc-price` flag to request a price in BTC instead of USD:

```
cmcap power-ledger -b
```

Or you can request the price in one of the ~30 other supported fiat currencies with `-c` or `--convert-to`:

```
cmcap request-network -cEUR
```

You can print a list of supported fiat currencies with `cmcap --fiat-currencies`.

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

The soft rate limit for the API is 10 requests per minute (for the currently used v1 API).


## CoinCap

[CoinCap.io](https://coincap.io) is a site similar to CoinMarketCap with an API that includes historical coin prices (with decreasing precision the further into the past you look).

To check past price of a given coin, pass the coin's symbol and a properly formatted timestamp:

```
coincap xmr "2018-04-01 13:00"
```

To check the current price, skip the timestamp:

```
coincap xmr
```

By default the price is printed in a verbose format that includes the requested coin symbol and the time of the returned price. Add a `-q/--quiet` option to only print the price as a single number (e.g. to pass it further to another script).

You can also use the `-b` or `--btc-price` flag to request a price in BTC instead of USD, or `-e` or `--eur-price` for EUR:

```
coincap xmr -b
coincap xmr -e
```

These are however only supported for current prices - past prices are only listed in USD.

In code:

```ruby
require 'cointools'  # or 'cointools/coincap'
coincap = CoinTools::CoinCap.new

result = coincap.get_price('XMR', Time.now - 86400)
puts "XMR yesterday: $#{result.usd_price} (#{result.time})"

result = coincap.get_current_price('XMR')
puts "XMR today: $#{result.usd_price} / €#{result.eur_price} / ₿#{result.btc_price}"
```

The result object contains the requested price and (for historical prices) the actual timestamp of the found price, which might slightly differ from the timestamp passed in the argument (the earlier the date, the less precise the result).

At the moment there don't seem to be any official rate limits for the API.


## Credits & contributing

Copyright © 2018 [Kuba Suder](https://mackuba.eu). Licensed under [MIT License](http://opensource.org/licenses/MIT).

If you'd like to help me extend the scripts with some additional features or add support for new services, [send me a pull request](https://github.com/mackuba/cointools/pulls).
