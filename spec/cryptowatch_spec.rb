require 'spec_helper'

describe CoinTools::Cryptowatch do
  subject { CoinTools::Cryptowatch.new }

  let(:exchanges_url) { "https://api.cryptowat.ch/exchanges" }

  def ticker_url(exchange, pair)
    "https://api.cryptowat.ch/markets/#{exchange}/#{pair}/price"
  end

  def stub(exchange, pair, params)
    stub_request(:get, ticker_url(exchange, pair)).to_return(params)
  end

  describe '#exchanges' do
    context 'when a correct response is returned' do
      before do
        stub_request(:get, exchanges_url).to_return(body: json({
          result: [
            { symbol: 'kraken', active: true },
            { symbol: 'bitcurex', active: false },
            { symbol: 'mtgox', active: false },
            { symbol: 'bitstamp', active: true }
          ]
        }))
      end

      it 'should return sorted symbols of active exchanges' do
        list = subject.exchanges

        list.should == ['bitstamp', 'kraken']
      end

      context 'when called again' do
        it 'should return the same list' do
          list1 = subject.exchanges
          list2 = subject.exchanges

          list1.should == list2
        end

        it 'should cache the response' do
          subject.exchanges
          subject.exchanges

          WebMock.should have_requested(:get, exchanges_url).once
        end
      end
    end

    it 'should send user agent headers' do
      stub_request(:get, exchanges_url).to_return(body: json({ result: [] }))

      subject.exchanges

      WebMock.should have_requested(:get, exchanges_url).with(headers: user_agent_header)
    end

    context 'when an invalid response is returned' do
      before do
        stub_request(:get, exchanges_url).to_return(status: [500, 'Internal Server Error'])
      end

      it 'should throw an exception' do
        proc {
          subject.exchanges
        }.should raise_error(CoinTools::Cryptowatch::InvalidResponseException, '500 Internal Server Error')
      end
    end
  end

  describe '#get_current_price' do
    context 'when a correct response is returned' do
      before do
        stub('kraken', 'btceur', body: json({ result: { price: 6000.0 }}))
      end

      it 'should return a data point with nil timestamp' do
        data = subject.get_current_price('kraken', 'btceur')

        data.time.should be_nil
        data.price.should == 6000.0
      end
    end

    it 'should send user agent headers' do
      stub('bitstamp', 'btcusd', body: json({ result: {}}))

      subject.get_current_price('bitstamp', 'btcusd')

      WebMock.should have_requested(:get, ticker_url('bitstamp', 'btcusd')).with(headers: user_agent_header)
    end

    context 'when status 400 is returned' do
      before do
        stub('bitstamp', 'btcusd', status: [400, 'Bad Request'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_current_price('bitstamp', 'btcusd')
        }.should raise_error(CoinTools::Cryptowatch::BadRequestException, '400 Bad Request')
      end
    end

    context 'when an invalid response is returned' do
      before do
        stub('bitstamp', 'btcusd', status: [500, 'Internal Server Error'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_current_price('bitstamp', 'btcusd')
        }.should raise_error(CoinTools::Cryptowatch::InvalidResponseException, '500 Internal Server Error')
      end
    end

  end
end
