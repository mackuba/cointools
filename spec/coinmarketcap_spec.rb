require 'spec_helper'

describe CoinTools::CoinMarketCap do
  subject { CoinTools::CoinMarketCap.new }

  let(:timestamp) { Time.now.round }
  let(:last_updated) { timestamp.to_i.to_s }
  let(:full_ticker_url) { "https://api.coinmarketcap.com/v1/ticker/?limit=0" }
  let(:listings_url) { "https://api.coinmarketcap.com/v2/listings/" }

  let(:listings) {[
    { id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin' },
    { id: 2, name: 'Ethereum', symbol: 'ETH', website_slug: 'ethereum' },
    { id: 10, name: 'Monero', symbol: 'XMR', website_slug: 'monero' },
    { id: 20, name: 'Request Network', symbol: 'REQ', website_slug: 'request-network' }
  ]}

  def ticker_url(symbol)
    "https://api.coinmarketcap.com/v1/ticker/#{symbol}/"
  end

  def stub(symbol, params)
    stub_request(:get, ticker_url(symbol)).to_return(params)
  end

  def stub_listings
    stub_request(:get, listings_url).to_return(body: json({
      data: [
        { id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin' },
        { id: 5, name: 'Ripple', symbol: 'XRP', website_slug: 'ripple' },
        { id: 10, name: 'Monero', symbol: 'XMR', website_slug: 'monero' },
        { id: 20, name: 'Request Network', symbol: 'REQ', website_slug: 'request-network' }
      ],
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
            data: [
              { id: 1, name: 'Bitcoin', symbol: 'BTC', website_slug: 'bitcoin' }
            ],
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

  describe '#get_price' do
    context 'if the passed coin symbol is an empty string' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price('')
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'if the passed coin symbol is nil' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price(nil)
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'when a correct response is returned' do
      before do
        stub('litecoin', body: json([
          { price_usd: '200.0', price_btc: '0.025', price_pln: '1000.0', last_updated: last_updated }
        ]))
      end

      it 'should return a data point' do
        data = subject.get_price('litecoin')

        data.time.should == timestamp
        data.usd_price.should == 200.0
        data.btc_price.should == 0.025
        data.converted_price.should be_nil
      end
    end

    it 'should send user agent headers' do
      stub('bitcoin', body: json([
        { price_usd: '20000.0', price_btc: '1.0', price_pln: '70000.0', last_updated: last_updated }
      ]))

      subject.get_price('bitcoin')

      WebMock.should have_requested(:get, ticker_url('bitcoin')).with(headers: user_agent_header)
    end

    it 'should not use the unsafe method JSON.load' do
      Exploit.should_not_receive(:json_creatable?)

      stub('litecoin', body: json([
        { price_usd: '200.0', price_btc: '0.025', price_pln: '1000.0', last_updated: last_updated,
          json_class: 'Exploit' }
      ]))

      subject.get_price('litecoin')
    end

    context 'when the json object is not an array' do
      before do
        stub('ethereum', body: json({ price_usd: 1000 }))
      end

      it 'should throw JSONError' do
        proc {
          subject.get_price('ethereum')
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include usd price' do
      before do
        stub('litecoin', body: json([
          { price_usd: nil, price_btc: '0.025', price_pln: '1000.0', last_updated: last_updated }
        ]))
      end

      it 'should raise NoDataError' do
        proc {
          subject.get_price('litecoin')
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when the json object does not include btc price' do
      before do
        stub('litecoin', body: json([
          { price_usd: '200.0', price_btc: nil, price_pln: '1000.0', last_updated: last_updated }
        ]))
      end

      it 'should raise NoDataError' do
        proc {
          subject.get_price('litecoin')
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when the json object does not include a timestamp' do
      before do
        stub('litecoin', body: json([
          { price_usd: '200.0', price_btc: '0.025', price_pln: '1000.0', last_updated: nil }
        ]))
      end

      it 'should raise NoDataError' do
        proc {
          subject.get_price('litecoin')
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when status 404 is returned' do
      before do
        stub('monero', status: [404, 'Not Found'])
      end

      it 'should throw UnknownCoinError' do
        proc {
          subject.get_price('monero')
        }.should raise_error(CoinTools::UnknownCoinError, '404 Not Found')
      end
    end

    context 'when status 4xx is returned' do
      before do
        stub('monero', status: [400, 'Bad Request'])
      end

      it 'should throw BadRequestError' do
        proc {
          subject.get_price('monero')
        }.should raise_error(CoinTools::BadRequestError, '400 Bad Request')
      end
    end

    context 'when status 5xx is returned' do
      before do
        stub('monero', status: [500, 'Internal Server Error'])
      end

      it 'should throw ServiceUnavailableError' do
        proc {
          subject.get_price('monero')
        }.should raise_error(CoinTools::ServiceUnavailableError)
      end
    end
  end

  describe '#get_price with convert_to' do
    context 'when a correct response is returned' do
      before do
        stub_request(:get, ticker_url('litecoin') + '?convert=PLN').to_return(body: json([
          { price_usd: '200.0', price_btc: '0.025', price_pln: '1000.0', last_updated: last_updated }
        ]))
      end

      it 'should return a data point with converted price' do
        data = subject.get_price('litecoin', convert_to: 'PLN')

        data.time.should == timestamp
        data.usd_price.should == 200.0
        data.btc_price.should == 0.025
        data.converted_price.should == 1000.0
      end
    end

    context 'when an unknown fiat currency code is passed' do
      it 'should not make any requests' do
        stub_request(:any, //)

        subject.get_price('litecoin', convert_to: 'XYZ') rescue nil

        WebMock.should_not have_requested(:get, //)
      end

      it 'should throw an exception' do
        proc {
          subject.get_price('litecoin', convert_to: 'XYZ')
        }.should raise_error(CoinTools::InvalidFiatCurrencyError)
      end
    end

    context 'when converted price is not included' do
      before do
        stub_request(:get, ticker_url('litecoin') + '?convert=PLN').to_return(body: json([
          { price_usd: '200.0', price_btc: '0.025', price_eur: '180.0', last_updated: last_updated }
        ]))
      end

      it 'should throw an exception' do
        proc {
          subject.get_price('litecoin', convert_to: 'PLN')
        }.should raise_error(CoinTools::NoDataError)
      end
    end
  end

  describe '#get_price_by_symbol' do
    context 'if the passed coin symbol is an empty string' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price_by_symbol('')
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'if the passed coin symbol is nil' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price_by_symbol(nil)
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'when a correct response is returned' do
      before do
        stub_request(:get, full_ticker_url).to_return(body: json([{
          symbol: 'LTC', price_usd: '200.0', price_btc: '0.025', price_pln: '1000.0', last_updated: last_updated
        }]))
      end

      it 'should return a data point' do
        data = subject.get_price_by_symbol('LTC')

        data.time.should == timestamp
        data.usd_price.should == 200.0
        data.btc_price.should == 0.025
        data.converted_price.should be_nil
      end
    end

    it 'should not use the unsafe method JSON.load' do
      Exploit.should_not_receive(:json_creatable?)

      stub_request(:get, full_ticker_url).to_return(body: json([{
        symbol: 'LTC', price_usd: '200.0', price_btc: '0.025', price_pln: '1000.0', last_updated: last_updated,
        json_class: 'Exploit'
      }]))

      subject.get_price_by_symbol('LTC')
    end

    it 'should send user agent headers' do
      stub_request(:get, full_ticker_url).to_return(body: json([
        { symbol: 'BTC', price_usd: '20000.0', price_btc: '1.0', price_pln: '70000.0', last_updated: last_updated }
      ]))

      subject.get_price_by_symbol('BTC')

      WebMock.should have_requested(:get, full_ticker_url).with(headers: user_agent_header)
    end

    context 'when the requested coin is not included on the list' do
      before do
        stub_request(:get, full_ticker_url).to_return(body: json([]))
      end

      it 'should throw an exception' do
        proc {
          subject.get_price_by_symbol('BCC')  # hey hey heyyy!!
        }.should raise_error(CoinTools::UnknownCoinError)
      end
    end

    context 'when the json object is not an array' do
      before do
        stub_request(:get, full_ticker_url).to_return(body: json({ price_usd: 1000 }))
      end

      it 'should throw JSONError' do
        proc {
          subject.get_price_by_symbol('ETH')
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include usd price' do
      before do
        stub_request(:get, full_ticker_url).to_return(body: json([
          { symbol: 'BTC', price_usd: nil, price_btc: '1.0', price_pln: '70000.0', last_updated: last_updated }
        ]))
      end

      it 'should raise NoDataError' do
        proc {
          subject.get_price_by_symbol('BTC')
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when the json object does not include btc price' do
      before do
        stub_request(:get, full_ticker_url).to_return(body: json([
          { symbol: 'BTC', price_usd: '20000.0', price_btc: nil, price_pln: '70000.0', last_updated: last_updated }
        ]))
      end

      it 'should raise NoDataError' do
        proc {
          subject.get_price_by_symbol('BTC')
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when status 400 is returned' do
      before do
        stub_request(:get, full_ticker_url).to_return(status: [400, 'Bad Request'])
      end

      it 'should throw BadRequestError' do
        proc {
          subject.get_price_by_symbol('XMR')
        }.should raise_error(CoinTools::BadRequestError, '400 Bad Request')
      end
    end

    context 'when a 5xx status is returned' do
      before do
        stub_request(:get, full_ticker_url).to_return(status: [500, 'Internal Server Error'])
      end

      it 'should throw ServiceUnavailableError' do
        proc {
          subject.get_price_by_symbol('XMR')
        }.should raise_error(CoinTools::ServiceUnavailableError)
      end
    end
  end

  describe '#get_price_by_symbol with convert_to' do
    context 'when a correct response is returned' do
      before do
        stub_request(:get, full_ticker_url + '&convert=PLN').to_return(body: json([{
          symbol: 'LTC', price_usd: '200.0', price_btc: '0.025', price_pln: '1000.0', last_updated: last_updated
        }]))
      end

      it 'should return a data point' do
        data = subject.get_price_by_symbol('LTC', convert_to: 'PLN')

        data.time.should == timestamp
        data.usd_price.should == 200.0
        data.btc_price.should == 0.025
        data.converted_price.should == 1000.0
      end
    end

    context 'when an unknown fiat currency code is passed' do
      it 'should not make any requests' do
        stub_request(:any, //)

        subject.get_price_by_symbol('LTC', convert_to: 'XYZ') rescue nil

        WebMock.should_not have_requested(:get, //)
      end

      it 'should throw an exception' do
        proc {
          subject.get_price_by_symbol('LTC', convert_to: 'XYZ')
        }.should raise_error(CoinTools::InvalidFiatCurrencyError)
      end
    end

    context 'when converted price is not included' do
      before do
        stub_request(:get, full_ticker_url + '&convert=PLN').to_return(body: json([{
          symbol: 'LTC', price_usd: '200.0', price_btc: '0.025', price_eur: '180.0', last_updated: last_updated
        }]))
      end

      it 'should throw an exception' do
        proc {
          subject.get_price_by_symbol('LTC', convert_to: 'PLN')
        }.should raise_error(CoinTools::NoDataError)
      end
    end
  end

end
