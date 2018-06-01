require 'spec_helper'

describe CoinTools::CoinMarketCap do
  subject { CoinTools::CoinMarketCap.new }

  let(:timestamp) { Time.now.round }
  let(:last_updated) { timestamp.to_i.to_s }
  let(:full_ticker_url) { "https://api.coinmarketcap.com/v1/ticker/?limit=0" }

  def ticker_url(symbol)
    "https://api.coinmarketcap.com/v1/ticker/#{symbol}/"
  end

  def stub(symbol, params)
    stub_request(:get, ticker_url(symbol)).to_return(params)
  end

  describe '#get_price' do
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

    context 'when status 404 is returned' do
      before do
        stub('monero', status: [404, 'Not Found'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_price('monero')
        }.should raise_error(CoinTools::BadRequestError, '404 Not Found')
      end
    end

    context 'when an invalid response is returned' do
      before do
        stub('monero', status: [500, 'Internal Server Error'])
      end

      it 'should throw an exception' do
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

    context 'when status 404 is returned' do
      before do
        stub_request(:get, full_ticker_url).to_return(status: [404, 'Not Found'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_price_by_symbol('XMR')
        }.should raise_error(CoinTools::BadRequestError, '404 Not Found')
      end
    end

    context 'when an invalid response is returned' do
      before do
        stub_request(:get, full_ticker_url).to_return(status: [500, 'Internal Server Error'])
      end

      it 'should throw an exception' do
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
