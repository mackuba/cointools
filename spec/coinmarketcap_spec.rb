require 'spec_helper'

describe CoinTools::CoinMarketCap do
  subject { CoinTools::CoinMarketCap.new }

  let(:timestamp) { Time.now.round - 300 }
  let(:last_updated) { timestamp.to_i }
  let(:listings_url) { "https://api.coinmarketcap.com/v2/listings/" }

  let(:listings) {[
    { id: 1, rank: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin' },
    { id: 5, rank: 3, name: 'Ripple', symbol: 'XRP', website_slug: 'ripple' },
    { id: 10, rank: 12, name: 'Monero', symbol: 'XMR', website_slug: 'monero' },
    { id: 20, rank: 50, name: 'Request Network', symbol: 'REQ', website_slug: 'request-network' }
  ]}

  def ticker_url(id, currency)
    "https://api.coinmarketcap.com/v2/ticker/#{id}/?convert=#{currency}"
  end

  def full_ticker_url(currency, start)
    "https://api.coinmarketcap.com/v2/ticker/?structure=array&sort=id&limit=100&convert=#{currency}&start=#{start}"
  end

  def stub_ticker(numeric_id, currency, params)
    stub_request(:get, ticker_url(numeric_id, currency)).to_return(params)
  end

  def stub_listings
    stub_request(:get, listings_url).to_return(body: json({
      data: listings,
      metadata: {}
    }))
  end

  describe '#load_listings' do
    context 'when a correct response is returned' do
      before { stub_listings }

      it 'should build the @id_map' do
        subject.load_listings

        id_map = subject.instance_variable_get('@id_map')
        id_map.should be_a(Hash)
        id_map.keys.sort.should == ['bitcoin', 'monero', 'request-network', 'ripple']

        id_map['ripple'].should_not be_nil
        id_map['ripple'].numeric_id.should == 5
        id_map['ripple'].symbol.should == 'XRP'
        id_map['ripple'].name.should == 'Ripple'
        id_map['ripple'].text_id.should == 'ripple'
      end

      it 'should build the @symbol_map' do
        subject.load_listings

        symbol_map = subject.instance_variable_get('@symbol_map')
        symbol_map.should be_a(Hash)
        symbol_map.keys.sort.should == ['BTC', 'REQ', 'XMR', 'XRP']

        symbol_map['XRP'].should_not be_nil
        symbol_map['XRP'].numeric_id.should == 5
        symbol_map['XRP'].symbol.should == 'XRP'
        symbol_map['XRP'].name.should == 'Ripple'
        symbol_map['XRP'].text_id.should == 'ripple'
      end

      it 'should return the number of listings' do
        subject.load_listings.should == listings.length
      end
    end

    it 'should not use the unsafe method JSON.load' do
      Exploit.should_not_receive(:json_creatable?)

      stub_request(:get, listings_url).to_return(body: json({
        data: [{ id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin', json_class: 'Exploit' }],
        metadata: {}
      }))

      subject.load_listings
    end

    it 'should send user agent headers' do
      stub_listings

      subject.load_listings

      WebMock.should have_requested(:get, listings_url).with(headers: user_agent_header)
    end

    context 'when called a second time' do
      before { stub_listings }

      it 'should make another request' do
        2.times { subject.load_listings }

        WebMock.should have_requested(:get, listings_url).twice
      end
    end

    context 'when the json object is not a hash' do
      before do
        stub_request(:get, listings_url).to_return(body: json(
          [{ id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin' }]
        ))
      end

      it 'should throw JSONError' do
        proc {
          subject.load_listings
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include a data field' do
      before do
        stub_request(:get, listings_url).to_return(body: json({
          metadata: {
            time: 1234
          }
        }))
      end

      it 'should throw JSONError' do
        proc {
          subject.load_listings
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include a metadata field' do
      before do
        stub_request(:get, listings_url).to_return(body: json({
          data: [
            { id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin' }
          ]
        }))
      end

      it 'should throw JSONError' do
        proc {
          subject.load_listings
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the data object is not an array' do
      before do
        stub_request(:get, listings_url).to_return(body: json(
          {
            data: {
              id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin'
            },
            metadata: {
              error: nil
            }
          }
        ))
      end

      it 'should throw JSONError' do
        proc {
          subject.load_listings
        }.should raise_error(CoinTools::JSONError)
      end
    end

    [:id, :name, :symbol, :website_slug].each do |key|
      context "when the record object does not include a(n) #{key}" do
        before do
          record = { id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin' }
          record.delete(key)

          stub_request(:get, listings_url).to_return(body: json({
            data: [record],
            metadata: {}
          }))
        end

        it 'should throw JSONError' do
          proc {
            subject.load_listings
          }.should raise_error(CoinTools::JSONError)
        end
      end
    end

    context 'when the metadata field includes an error' do
      before do
        stub_request(:get, listings_url).to_return(body: json(
          {
            data: nil,
            metadata: {
              error: 'something went wrong'
            }
          }
        ))
      end

      it 'should throw BadRequestError' do
        proc {
          subject.load_listings
        }.should raise_error(CoinTools::BadRequestError)
      end
    end

    context 'when status 4xx is returned' do
      before do
        stub_request(:get, listings_url).to_return(status: [400, 'Bad Request'])
      end

      it 'should throw BadRequestError' do
        proc {
          subject.load_listings
        }.should raise_error(CoinTools::BadRequestError, '400 Bad Request')
      end
    end

    context 'when status 5xx is returned' do
      before do
        stub_request(:get, listings_url).to_return(status: [500, 'Internal Server Error'])
      end

      it 'should throw ServiceUnavailableError' do
        proc {
          subject.load_listings
        }.should raise_error(CoinTools::ServiceUnavailableError, '500 Internal Server Error')
      end
    end
  end

  describe 'id_map' do
    before { stub_listings }

    context 'if listings were not loaded' do
      it 'should load listings' do
        subject.id_map

        WebMock.should have_requested(:get, listings_url).once
      end

      it 'should return an id map' do
        subject.id_map.should be_an(Hash)
        subject.id_map.length.should == 4
        subject.id_map.keys.sort.should == ['bitcoin', 'monero', 'request-network', 'ripple']
      end
    end

    context 'if listings were loaded before' do
      before { subject.load_listings }

      it 'should not load them again' do
        subject.id_map

        WebMock.should have_requested(:get, listings_url).once
      end

      it 'should return an id map' do
        subject.id_map.should be_an(Hash)
        subject.id_map.length.should == 4
        subject.id_map.keys.sort.should == ['bitcoin', 'monero', 'request-network', 'ripple']
      end
    end
  end

  describe 'symbol_map' do
    before { stub_listings }

    context 'if listings were not loaded' do
      it 'should load listings' do
        subject.symbol_map

        WebMock.should have_requested(:get, listings_url).once
      end

      it 'should return a symbol map' do
        subject.symbol_map.should be_an(Hash)
        subject.symbol_map.length.should == 4
        subject.symbol_map.keys.sort.should == ['BTC', 'REQ', 'XMR', 'XRP']
      end
    end

    context 'if listings were loaded before' do
      before { subject.load_listings }

      it 'should not load them again' do
        subject.symbol_map

        WebMock.should have_requested(:get, listings_url).once
      end

      it 'should return a symbol map' do
        subject.symbol_map.should be_an(Hash)
        subject.symbol_map.length.should == 4
        subject.symbol_map.keys.sort.should == ['BTC', 'REQ', 'XMR', 'XRP']
      end
    end
  end

  shared_examples 'get_price behavior' do |method, param|
    before { stub_listings }

    context 'if the passed coin symbol is an empty string' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.send(method, '')
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'if the passed coin symbol is nil' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.send(method, nil)
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'when a correct response is returned' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: {
              'USD': { price: '8000.0' },
              'BTC': { price: '1.0' },
            },
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should return a data point' do
        data = subject.send(method, param)

        data.last_updated.should == timestamp
        data.usd_price.should == 8000.0
        data.btc_price.should == 1.0
        data.converted_price.should be_nil
      end
    end

    it 'should send user agent headers' do
      stub_ticker(1, 'BTC', body: json({
        data: listings[0].merge({
          quotes: { 'USD': { price: '8000.0' }},
          last_updated: last_updated
        }),
        metadata: {}
      }))

      subject.send(method, param)

      WebMock.should have_requested(:get, ticker_url(1, 'BTC')).with(headers: user_agent_header)
    end

    it 'should not use the unsafe method JSON.load' do
      Exploit.should_not_receive(:json_creatable?)

      stub_ticker(1, 'BTC', body: json({
        data: listings[0].merge({
          quotes: { 'USD': { price: '8000.0', json_class: 'Exploit' }},
          last_updated: last_updated
        }),
        metadata: {}
      }))

      subject.send(method, param)
    end

    context 'when the json object is not a hash' do
      before do
        stub_ticker(1, 'BTC', body: json([{}]))
      end

      it 'should throw JSONError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include a data field' do
      before do
        stub_ticker(1, 'BTC', body: json({
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include a metadata field' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: {
              'USD': { price: '8000.0' },
              'BTC': { price: '1.0' },
            },
            last_updated: last_updated
          })
        }))
      end

      it 'should throw JSONError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the data object is not a hash' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: [{}],
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the metadata field includes an error' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: nil,
          metadata: { error: 'we have suffered a stolen' }
        }))
      end

      it 'should throw BadRequestError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::BadRequestError)
      end
    end

    context 'when the rank field is missing' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            rank: nil,
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the rank field is not an integer' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            rank: '*',
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the rank field is not a positive number' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            rank: 0,
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the quotes list is missing' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: nil,
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the quotes list is not a hash' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: [
              { 'USD': { price: '8000.0' }},
              { 'BTC': { price: '1.0' }},
            ],
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the quotes info for USD is missing' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: {
              'USD': nil,
              'BTC': { price: '1.0' },
            },
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the quotes info for USD is not a hash' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: {
              'USD': 8000.0,
              'BTC': { price: '1.0' },
            },
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the quotes info for BTC is missing' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: {
              'USD': { price: 8000.0 },
              'BTC': nil,
            },
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should return a nil price' do
        data = nil

        proc { data = subject.send(method, param) }.should_not raise_error

        data.btc_price.should be_nil
      end
    end

    context 'when the quotes info for BTC is not a hash' do
      before do
        stub_ticker(1, 'BTC', body: json({
          data: listings[0].merge({
            quotes: {
              'USD': { price: '8000.0' },
              'BTC': 1
            },
            last_updated: last_updated
          }),
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
      end
    end

    [:id, :name, :symbol, :website_slug].each do |key|
      context "when the record object does not include a(n) #{key} key" do
        before do
          data = {
            data: listings[0].merge({
              quotes: {
                'USD': { price: '8000.0' },
                'BTC': { price: '1.0' },
              },
              last_updated: last_updated
            }),
            metadata: {}
          }

          data[:data][key] = nil

          stub_ticker(1, 'BTC', body: json(data))
        end

        it 'should throw JSONError' do
          proc { subject.send(method, param) }.should raise_error(CoinTools::JSONError)
        end
      end
    end

    context 'when status 404 is returned' do
      before do
        stub_ticker(1, 'BTC', status: [404, 'Not Found'])
      end

      it 'should throw UnknownCoinError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::UnknownCoinError, '404 Not Found')
      end
    end

    context 'when status 4xx is returned' do
      before do
        stub_ticker(1, 'BTC', status: [400, 'Bad Request'])
      end

      it 'should throw BadRequestError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::BadRequestError, '400 Bad Request')
      end
    end

    context 'when status 5xx is returned' do
      before do
        stub_ticker(1, 'BTC', status: [500, 'Internal Server Error'])
      end

      it 'should throw ServiceUnavailableError' do
        proc {
          subject.send(method, param)
        }.should raise_error(CoinTools::ServiceUnavailableError, '500 Internal Server Error')
      end
    end

    context 'with convert_to' do
      context 'when a correct response is returned' do
        before do
          stub_ticker(1, 'EUR', body: json({
            data: listings[0].merge({
              quotes: {
                'USD': { price: '8000.0' },
                'EUR': { price: '6000.0' },
              },
              last_updated: last_updated
            }),
            metadata: {}
          }))
        end

        it 'should return a data point with converted price' do
          data = subject.send(method, param, convert_to: 'EUR')

          data.last_updated.should == timestamp
          data.usd_price.should == 8000.0
          data.btc_price.should be_nil
          data.converted_price.should == 6000.0
        end
      end

      context 'when a lowercase currency code is passed' do
        before do
          stub_ticker(1, 'EUR', body: json({
            data: listings[0].merge({
              quotes: {
                'USD': { price: '8000.0' },
                'EUR': { price: '6000.0' },
              },
              last_updated: last_updated
            }),
            metadata: {}
          }))
        end

        it 'should make it uppercase' do
          data = subject.send(method, param, convert_to: 'eur')

          data.usd_price.should == 8000.0
          data.btc_price.should be_nil
          data.converted_price.should == 6000.0
        end
      end

      context 'when an unknown fiat currency code is passed' do
        it 'should not make any requests' do
          stub_request(:any, //)

          subject.send(method, param, convert_to: 'XYZ') rescue nil

          WebMock.should_not have_requested(:get, //)
        end

        it 'should throw an exception' do
          proc {
            subject.send(method, param, convert_to: 'XYZ')
          }.should raise_error(CoinTools::InvalidFiatCurrencyError)
        end
      end

      context 'when converted price is not included' do
        before do
          stub_ticker(1, 'EUR', body: json({
            data: listings[0].merge({
              quotes: {
                'USD': { price: '8000.0' },
                'PLN': { price: '30000.0' },
              },
              last_updated: last_updated
            }),
            metadata: {}
          }))
        end

        it 'should return a nil price' do
          data = subject.send(method, param, convert_to: 'EUR')
          data.converted_price.should be_nil
        end
      end

      context 'when converted price quote is not a hash' do
        before do
          stub_ticker(1, 'EUR', body: json({
            data: listings[0].merge({
              quotes: {
                'USD': { price: '8000.0' },
                'EUR': 7000.0,
              },
              last_updated: last_updated
            }),
            metadata: {}
          }))
        end

        it 'should throw JSONError' do
          proc { subject.send(method, param, convert_to: 'EUR') }.should raise_error(CoinTools::JSONError)
        end
      end
    end
  end

  describe '#get_price' do
    include_examples 'get_price behavior', :get_price, 'bitcoin'

    context 'if a coin with given id does not exist' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price('bitcoin-cash')
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end
  end

  describe '#get_price_by_symbol' do
    include_examples 'get_price behavior', :get_price_by_symbol, 'BTC'

    context 'if a coin with given symbol does not exist' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price('BCC')  # hey hey heyyy!!
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end
  end

  describe '#get_all_prices' do
    let(:number_of_coins) { 250 }

    let(:listings) {
      ids = (1..(number_of_coins*2)).to_a.shuffle.first(number_of_coins).sort

      (1..number_of_coins).map { |n|
        id = ids.shift

        {
          'id' => id,
          'name' => "Coin #{id}",
          'symbol' => "C#{id.to_s.rjust(3, '0')}",
          'website_slug' => "c-#{id.to_s.rjust(3, '0')}"
        }
      }
    }

    def all_data(convert_to)
      ranks = (1..number_of_coins).to_a.shuffle

      (0...number_of_coins).map { |n|
        listings[n].merge({
          'rank' => ranks.shift,
          'last_updated' => last_updated,
          'quotes' => {
            'USD' => {
              'price' => rand(10000),
              'market_cap' => rand(1_000_000_000),
            },
            convert_to => {
              'price' => convert_to == 'BTC' ? rand : rand(10000),
            },
          },
        })
      }
    end

    let(:btc_data) { all_data('BTC') }
    let(:eur_data) { all_data('EUR') }

    def stub_full_ticker(convert_to, start, data, params = {})
      stub_request(:get, full_ticker_url(convert_to, start)).to_return({
        body: json({
          data: data,
          metadata: {}
        })
      }.merge(params))
    end

    before do
      stub_request(:get, listings_url).to_return(body: json({
        data: listings,
        metadata: {}
      }))
    end

    context 'when all pages return data correctly' do
      before do
        stub_full_ticker('BTC', 0, btc_data[0...100])
        stub_full_ticker('BTC', 100, btc_data[100...200])
        stub_full_ticker('BTC', 200, btc_data[200...250])
        stub_full_ticker('BTC', 250, nil, { status: [404, 'Not Found'] })
      end

      it 'should return a list of all coins, sorted by rank' do
        data = subject.get_all_prices

        data.should be_an(Array)
        data.length.should == number_of_coins

        sorted_json = btc_data.sort_by { |j| j['rank'] }

        data.each_with_index do |coin, i|
          json = sorted_json[i]
          coin.numeric_id.should == json['id']
          coin.name.should == json['name']
          coin.symbol.should == json['symbol']
          coin.text_id.should == json['website_slug']
          coin.rank.should == json['rank']
          coin.usd_price.should == json['quotes']['USD']['price']
          coin.btc_price.should == json['quotes']['BTC']['price']
          coin.market_cap.should == json['quotes']['USD']['market_cap']
        end
      end
    end

    it 'should send user agent headers' do
      stub_full_ticker('BTC', 0, btc_data[0...10])
      stub_full_ticker('BTC', 10, nil, { status: [404, 'Not Found'] })

      subject.get_all_prices

      WebMock.should have_requested(:get, full_ticker_url('BTC', 0)).with(headers: user_agent_header)
      WebMock.should have_requested(:get, full_ticker_url('BTC', 10)).with(headers: user_agent_header)
    end

    it 'should not use the unsafe method JSON.load' do
      Exploit.should_not_receive(:json_creatable?)

      stub_full_ticker('BTC', 0, [btc_data[0].merge(json_class: 'Exploit')])
      stub_full_ticker('BTC', 1, nil, { status: [404, 'Not Found'] })

      subject.get_all_prices
    end

    context 'if an empty page is returned' do
      before do
        stub_full_ticker('BTC', 0, btc_data[0...100])
        stub_full_ticker('BTC', 100, btc_data[100...200])
        stub_full_ticker('BTC', 200, []).then.to_raise(StandardError.new('unexpected second request'))
      end

      it 'should stop downloading and return the data' do
        data = nil

        proc { data = subject.get_all_prices }.should_not raise_error

        data.should be_an(Array)
        data.length.should == 200
      end
    end

    context 'if a block is passed' do
      before do
        stub_full_ticker('BTC', 0, btc_data[0...100])
        stub_full_ticker('BTC', 100, btc_data[100...120])
        stub_full_ticker('BTC', 120, nil, { status: [404, 'Not Found'] })
      end

      it 'should yield each batch separately to the block' do
        received = []
        subject.get_all_prices { |b| received << b }

        received.length.should == 2
        received[0].should be_an(Array)
        received[1].should be_an(Array)
        received[0].map(&:numeric_id).should == btc_data[0...100].map { |j| j['id'] }
        received[1].map(&:numeric_id).should == btc_data[100...120].map { |j| j['id'] }
      end
    end

    context 'when the json object is not a hash' do
      before do
        stub_full_ticker('BTC', 0, nil, body: json([{}]))
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include a data field' do
      before do
        stub_full_ticker('BTC', 0, nil, body: json({
          metadata: {}
        }))
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include a metadata field' do
      before do
        stub_full_ticker('BTC', 0, nil, body: json({
          data: [btc_data[0]],
          metadata: nil
        }))
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the data object is not an array' do
      before do
        stub_full_ticker('BTC', 0, btc_data[0])
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the metadata field includes an error' do
      before do
        stub_full_ticker('BTC', 0, nil, body: json({
          data: nil,
          metadata: { error: 'funds are not safu' }
        }))
      end

      it 'should throw BadRequestError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::BadRequestError)
      end
    end

    context 'if the rank field is missing in json' do
      before do
        data = btc_data[0...10]
        data[6]['rank'] = nil
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the rank field is not an integer' do
      before do
        data = btc_data[0...10]
        data[8]['rank'] = 'one'
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the rank field is negative' do
      before do
        data = btc_data[0...10]
        data[2]['rank'] = -5
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the quotes field is missing' do
      before do
        data = btc_data[0...10]
        data[2].delete('quotes')
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the quotes field is not a hash' do
      before do
        data = btc_data[0...10]
        data[2]['quotes'] = [8000, 0.5]
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the quotes hash does not include USD' do
      before do
        data = btc_data[0...10]
        data[8]['quotes']['USD'] = nil
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the quotes info for USD is not a hash' do
      before do
        data = btc_data[0...10]
        data[8]['quotes']['USD'] = [8000, 0.5]
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the quotes hash does not include BTC' do
      before do
        data = btc_data[0...10]
        data[8]['quotes']['BTC'] = nil
        stub_full_ticker('BTC', 0, data)
        stub_full_ticker('BTC', 10, [])
      end

      it 'should return nil price' do
        data = nil

        proc { data = subject.get_all_prices }.should_not raise_error

        data.sort_by(&:numeric_id)[8].btc_price.should be_nil
      end
    end

    context 'if the quotes info for BTC is not a hash' do
      before do
        data = btc_data[0...10]
        data[8]['quotes']['BTC'] = [0.5]
        stub_full_ticker('BTC', 0, data)
      end

      it 'should throw JSONError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'if the timestamp field is nil' do
      before do
        data = btc_data[0...10]
        data[7]['last_updated'] = nil
        stub_full_ticker('BTC', 0, data)
        stub_full_ticker('BTC', 10, [])
      end

      it 'should return nil for date' do
        data = nil

        proc { data = subject.get_all_prices }.should_not raise_error

        data.sort_by(&:numeric_id)[7].last_updated.should be_nil
      end
    end

    [:id, :name, :symbol, :website_slug].each do |key|
      context "when a record object does not include a(n) #{key} key" do
        before do
          data = btc_data[0...10]
          data[3][key] = nil
          stub_full_ticker('BTC', 0, data)
        end

        it 'should throw JSONError' do
          proc { subject.get_all_prices }.should raise_error(CoinTools::JSONError)
        end
      end
    end

    context 'when status 4xx is returned' do
      before do
        stub_full_ticker('BTC', 0, nil, status: [400, 'Bad Request'])
      end

      it 'should throw BadRequestError' do
        proc { subject.get_all_prices }.should raise_error(CoinTools::BadRequestError, '400 Bad Request')
      end
    end

    context 'when status 5xx is returned' do
      before do
        stub_full_ticker('BTC', 0, nil, status: [500, 'Internal Server Error'])
      end

      it 'should throw ServiceUnavailableError' do
        proc {
          subject.get_all_prices
        }.should raise_error(CoinTools::ServiceUnavailableError, '500 Internal Server Error')
      end
    end

    context 'with convert_to' do
      context 'when a correct response is returned' do
        before do
          stub_full_ticker('EUR', 0, eur_data[0...100])
          stub_full_ticker('EUR', 100, eur_data[100...140])
          stub_full_ticker('EUR', 140, nil, { status: [404, 'Not Found'] })
        end

        it 'should include converted price in the results' do
          data = subject.get_all_prices(convert_to: 'EUR')

          data.should be_an(Array)
          data.length.should == 140

          sorted_json = eur_data[0...140].sort_by { |j| j['rank'] }

          data.each_with_index do |coin, i|
            json = sorted_json[i]
            coin.converted_price.should == json['quotes']['EUR']['price']
          end
        end

        it 'should not include BTC price' do
          data = subject.get_all_prices(convert_to: 'EUR')

          data.should be_an(Array)

          data.each do |coin|
            coin.btc_price.should be_nil
          end
        end
      end

      context 'when a lowercase currency code is passed' do
        before do
          stub_full_ticker('EUR', 0, eur_data[0...100])
          stub_full_ticker('EUR', 100, eur_data[100...140])
          stub_full_ticker('EUR', 140, nil, { status: [404, 'Not Found'] })
        end

        it 'should make it uppercase' do
          data = subject.get_all_prices(convert_to: 'eur')

          data.should be_an(Array)
          data.length.should == 140

          sorted_json = eur_data[0...140].sort_by { |j| j['rank'] }

          data.each_with_index do |coin, i|
            json = sorted_json[i]
            coin.converted_price.should == json['quotes']['EUR']['price']
          end
        end
      end

      context 'when an unknown fiat currency code is passed' do
        it 'should not make any requests' do
          stub_request(:any, //)

          subject.get_all_prices(convert_to: 'FBI') rescue nil

          WebMock.should_not have_requested(:get, //)
        end

        it 'should throw an exception' do
          proc {
            subject.get_all_prices(convert_to: 'FBI')
          }.should raise_error(CoinTools::InvalidFiatCurrencyError)
        end
      end

      context 'when converted price is not included' do
        before do
          stub_full_ticker('EUR', 0, btc_data[0...60])
          stub_full_ticker('EUR', 60, nil, { status: [404, 'Not Found'] })
        end

        it 'should return a nil price' do
          data = subject.get_all_prices(convert_to: 'EUR')

          data.should be_an(Array)
          data.length.should == 60

          data.each do |coin|
            coin.converted_price.should be_nil
            coin.btc_price.should be_nil
          end
        end
      end

      context 'when converted price quote is not a hash' do
        before do
          data = eur_data[0...20]
          data[7]['quotes']['EUR'] = '6000.0'

          stub_full_ticker('EUR', 0, data)
        end

        it 'should throw JSONError' do
          proc { subject.get_all_prices(convert_to: 'EUR') }.should raise_error(CoinTools::JSONError)
        end
      end
    end
  end
end
