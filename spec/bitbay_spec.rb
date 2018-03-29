require 'spec_helper'

describe CoinTools::BitBay do
  subject { CoinTools::BitBay.new }

  def ticker_url(symbol)
    "https://bitbay.net/API/Public/#{symbol}/ticker.json"
  end

  def stub(symbol, params)
    stub_request(:get, ticker_url(symbol)).to_return(params)
  end

  describe '#get_price' do
    context 'when a correct response is returned' do
      before do
        stub('ltcusd', body: json(last: 120.5))
      end

      it 'should return a data point' do
        data = subject.get_price('ltcusd')

        data.should be_a(CoinTools::BitBay::DataPoint)
        data.price.should == 120.5
      end
    end

    it 'should send user agent headers' do
      stub('ltceur', body: json(last: 50.0))

      subject.get_price('ltceur')

      WebMock.should have_requested(:get, ticker_url('ltceur')).with(headers: user_agent_header)
    end

    context 'when an error code is returned' do
      before do
        stub('btcpln', body: json(code: 512, message: 'Something went wrong'))
      end

      it 'should throw an exception' do
        proc {
          subject.get_price('btcpln')
        }.should raise_error(CoinTools::BitBay::ErrorResponseException, '512 Something went wrong')
      end
    end

    context 'when an invalid response is returned' do
      before do
        stub('btcpln', status: [500, 'Internal Server Error'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_price('btcpln')
        }.should raise_error(CoinTools::BitBay::InvalidResponseException)
      end
    end
  end
end
