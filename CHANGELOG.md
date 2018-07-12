#### Version 0.5.0 (12.07.2018)

* switched to CoinMarketCap API v2, CMC's `get_price` and `get_price_by_symbol` calls now return data like coin name/symbol, rank and market cap
* new `get_all_prices` method in CMC that returns all 1600+ coins sorted by rank
* renamed `--list-exchanges` to `--exchanges`, `--list-markets` to `--markets`, `--list-fiat-currencies` to `--fiat-currencies`, `--fiat-currency` to `--convert-to`
* all commands print verbose output by default, use `--quiet/-q` to print only the price
* time can be passed as a string to `get_price` methods
* improved error handling
* added a huge amount of tests

#### Version 0.4.0 (23.05.2018)

* added CoinCap.io class and `coincap` command
* renamed CoinMarketCap command to `cmcap`
* removed BitBay class and command - BitBay is now supported on Cryptowatch (including past prices since March)
* fixed CoinMarketCap calls with currency conversion
* added "fast" method for Cryptowat.ch
* include API time allowance in Cryptowat.ch responses

#### Version 0.3.0 (26.03.2018)

* added BitBay class and `bitbay-price` command

#### Version 0.2.1 (6.03.2018)

* changed license to MIT

#### Version 0.2.0 (29.01.2018)

* added CoinMarketCap class & `coinmcap` binary

#### Version 0.1.2 (24.01.2018)

* fixed `--help` command

#### Version 0.1.1 (24.01.2018)

* first working release
