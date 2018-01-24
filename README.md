# Cointools

This is a collection of Ruby scripts and library classes that let you check cryptocurrency prices on various services (currently Cryptowatch).

## Installation

To use the scripts from the command line, install the gem:

```
gem install cointools
```

To use the code as a library, add it to your Gemfile:

```ruby
gem 'cointools'
```

## Usage

### [Cryptowatch](https://cryptowat.ch)

To check past price of a given coin on a chosen exchange, pass the exchange and market name and a properly formatted timestamp:

```
cryptowatch bitfinex btcusd "2017-12-17 13:00"
```

To check the current price, skip the timestamp:

```
cryptowatch bitfinex btcusd
```

In code:

```ruby
require 'cointools'
cryptowatch = CoinTools::Cryptowatch.new

result = cryptowatch.get_price('kraken', 'btceur', Time.now - 86400)
puts "Yesterday: #{result.price}"

result = cryptowatch.get_current_price('kraken', 'btceur')
puts "Today: #{result.price}"
```

The result object contains the requested price and (for historical prices) the actual timestamp of the found price, which might slightly differ from the timestamp passed in the argument (the earlier the date, the less precise the result).


## Credits & contributing

Copyright © 2018 [Kuba Suder](https://mackuba.eu). Licensed under [Very Simple Public License](https://github.com/mackuba/cointools/blob/master/VSPL-LICENSE.txt), my custom license that's basically a simplified version of the MIT license that fits in 3 lines.

If you'd like to help me extend the scripts with some additional features or add support for new services, [send me a pull request](https://github.com/mackuba/cointools/pulls).
