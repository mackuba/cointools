require 'spec_helper'

describe CoinTools::CoinCap do
  include TestHelpers

  subject { CoinTools::CoinCap.new }

  let(:some_data_point) { [1527089745158, 200.0] }

  def ticker_url(symbol)
    "https://coincap.io/page/#{symbol}"
  end

  def history_url(symbol, period)
    if period
      "https://coincap.io/history/#{period}day/#{symbol}"
    else
      "https://coincap.io/history/#{symbol}"
    end
  end

  def stub_ticker(symbol, params)
    stub_request(:get, ticker_url(symbol)).to_return(params)
  end

  def stub_history(symbol, period, params)
    stub_request(:get, history_url(symbol, period)).to_return(params)
  end

  describe '#get_current_price' do
    context 'if the passed coin symbol is an empty string' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_current_price('')
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'if the passed coin symbol is nil' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_current_price(nil)
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'when a correct response is returned' do
      before do
        stub_ticker('XMR', body: json({ price_usd: 200.0, price_eur: 150.0, price_btc: 0.002 }))
      end

      it 'should return a data point' do
        data = subject.get_current_price('XMR')

        data.usd_price.should == 200.0
      end

      it 'should include BTC price' do
        data = subject.get_current_price('XMR')

        data.btc_price.should == 0.002
      end

      it 'should include EUR price' do
        data = subject.get_current_price('XMR')

        data.eur_price.should == 150.0
      end

      it 'should have empty timestamp' do
        data = subject.get_current_price('XMR')

        data.time.should be_nil
      end
    end

    it 'should not use the unsafe method JSON.load' do
      Exploit.should_not_receive(:json_creatable?)
      stub_ticker('XMR', body: json({ price_usd: 666, json_class: 'Exploit' }))

      subject.get_current_price('XMR')
    end

    it 'should automatically make the symbol uppercase' do
      stub_ticker('XMR', body: json({ price_usd: 200.0 }))

      proc { subject.get_current_price('xmr') }.should_not raise_error
    end

    it 'should send user agent headers' do
      stub_ticker('XMR', body: json({ price_usd: 200.0 }))

      subject.get_current_price('XMR')

      WebMock.should have_requested(:get, ticker_url('XMR')).with(headers: user_agent_header)
    end

    context 'when an empty hash is returned' do
      before do
        stub_ticker('XMR', body: '{}')
      end

      it 'should throw UnknownCoinError' do
        proc {
          subject.get_current_price('XMR')
        }.should raise_error(CoinTools::UnknownCoinError)
      end
    end

    context 'when null response is returned' do
      before do
        stub_ticker('XMR', body: 'null')
      end

      it 'should throw UnknownCoinError' do
        proc {
          subject.get_current_price('XMR')
        }.should raise_error(CoinTools::UnknownCoinError)
      end
    end

    context 'when the json object is not a hash' do
      before do
        stub_ticker('XMR', body: '[1, 2, 3]')
      end

      it 'should throw JSONError' do
        proc {
          subject.get_current_price('XMR')
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include any prices' do
      before do
        stub_ticker('XMR', body: json({ id: 'XMR' }))
      end

      it 'should throw NoDataError' do
        proc {
          subject.get_current_price('XMR')
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when status 400 is returned' do
      before do
        stub_ticker('XMR', status: [400, 'Bad Request'])
      end

      it 'should throw BadRequestError' do
        proc {
          subject.get_current_price('XMR')
        }.should raise_error(CoinTools::BadRequestError, '400 Bad Request')
      end
    end

    context 'when status 5xx is returned' do
      before do
        stub_ticker('XMR', status: [500, 'Internal Server Error'])
      end

      it 'should throw ServiceUnavailableError' do
        proc {
          subject.get_current_price('XMR')
        }.should raise_error(CoinTools::ServiceUnavailableError, '500 Internal Server Error')
      end
    end
  end

  describe '#get_price' do
    context 'when time is nil' do
      it 'should forward the request to get_current_price' do
        subject.should_receive(:get_current_price).with('LTC').and_return(500.0)

        subject.get_price('LTC', nil).should == 500.0
      end
    end

    context 'when time is not set' do
      it 'should forward the request to get_current_price' do
        subject.should_receive(:get_current_price).with('LTC').and_return(300.0)

        subject.get_price('LTC').should == 300.0
      end
    end

    context 'when date is too far in the past' do
      it 'should throw InvalidDateError' do
        proc {
          subject.get_price('LTC', Time.new(2004, 5, 1))
        }.should raise_error(CoinTools::InvalidDateError)
      end
    end

    context 'when a future date is passed' do
      it 'should throw InvalidDateError' do
        proc {
          subject.get_price('LTC', Time.now + 86400)
        }.should raise_error(CoinTools::InvalidDateError)
      end
    end

    context 'if the passed coin symbol is an empty string' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price('', Time.now + 86400)
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    context 'if the passed coin symbol is nil' do
      it 'should throw InvalidSymbolError' do
        proc {
          subject.get_price(nil, Time.now + 86400)
        }.should raise_error(CoinTools::InvalidSymbolError)
      end
    end

    it 'should send user agent headers' do
      stub_history('XMR', nil, body: json({ price: [some_data_point] }))

      subject.get_price('XMR', Time.new(2017, 1, 1))

      WebMock.should have_requested(:get, history_url('XMR', nil)).with(headers: user_agent_header)
    end

    it 'should automatically make the symbol uppercase' do
      stub_history('XMR', nil, body: json({ price: [some_data_point] }))

      proc { subject.get_price('xmr', Time.new(2017, 1, 1)) }.should_not raise_error
    end

    context 'when the date is more than a year ago' do
      let(:time) { Time.now - 86400 * 400 }

      it 'should call the base history endpoint' do
        stub_history('XMR', nil, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time) }.should_not raise_error
      end
    end

    context 'when the date is less than a year ago' do
      let(:time) { Time.now - 86400 * 30 * 9 }

      it 'should call the 365day endpoint' do
        stub_history('XMR', 365, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time) }.should_not raise_error
      end
    end

    context 'when the date is less than half a year ago' do
      let(:time) { Time.now - 86400 * 30 * 5 }

      it 'should call the 180day endpoint' do
        stub_history('XMR', 180, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 90 days ago' do
      let(:time) { Time.now - 86400 * 60 }

      it 'should call the 90day endpoint' do
        stub_history('XMR', 90, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 30 days ago' do
      let(:time) { Time.now - 86400 * 28 }

      it 'should call the 30day endpoint' do
        stub_history('XMR', 30, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time) }.should_not raise_error
      end
    end

    context 'when the date is less than a week ago' do
      let(:time) { Time.now - 86400 * 5 }

      it 'should call the 7day endpoint' do
        stub_history('XMR', 7, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time) }.should_not raise_error
      end
    end

    context 'when the date is less than a day ago' do
      let(:time) { Time.now - 12 * 3600 }

      it 'should call the 1day endpoint' do
        stub_history('XMR', 1, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time) }.should_not raise_error
      end
    end

    context 'when the date is passed as a string' do
      let(:time) { Time.now - 86400 * 5 }
      let(:time_string) { time.strftime('%Y-%m-%d %H:%M:%S') }

      it 'should convert it to a time object automatically' do
        stub_history('XMR', 7, body: json({ price: [some_data_point] }))

        proc { subject.get_price('XMR', time_string) }.should_not raise_error
      end
    end

    context 'when a correct response is returned' do
      let(:time) { Time.now - 3600 }

      before do
        stub_history('XMR', 1, body: json({
          price: [
            [(time - 80).to_i * 1000, 199],
            [(time - 20).to_i * 1000, 201],
            [(time + 40).to_i * 1000, 203],
          ]
        }))
      end

      it 'should return a price and timestamp closest to the requested time' do
        data = subject.get_price('XMR', time)

        data.usd_price.should == 201.0
        data.time.to_i.should == time.to_i - 20
      end
    end

    it 'should not use the unsafe method JSON.load' do
      Exploit.should_not_receive(:json_creatable?)
      stub_history('XMR', 1, body: json({ price: [[0, 0]], json_class: 'Exploit' }))

      subject.get_price('XMR', Time.now - 3600)
    end

    context 'when an empty hash is returned' do
      before do
        stub_history('XMR', 1, body: '{}')
      end

      it 'should throw UnknownCoinError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::UnknownCoinError)
      end
    end

    context 'when null response is returned' do
      before do
        stub_history('XMR', 1, body: 'null')
      end

      it 'should throw UnknownCoinError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::UnknownCoinError)
      end
    end

    context 'when the json object is not a hash' do
      before do
        stub_history('XMR', 1, body: '[1, 2, 3]')
      end

      it 'should throw JSONError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the json object does not include a "price" key' do
      before do
        stub_history('XMR', 1, body: json({ market_cap: [[12345, 10000]] }))
      end

      it 'should throw JSONError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the price set is not an array' do
      before do
        stub_history('XMR', 1, body: json({ market_cap: [[12345, 10000]], price: { "USD": 10000 }}))
      end

      it 'should throw JSONError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::JSONError)
      end
    end

    context 'when the price set is empty' do
      let(:time) { Time.now - 3600 }

      before do
        stub_history('XMR', 1, body: json({
          price: []
        }))
      end

      it 'should throw NoDataError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when the price returned is null' do
      let(:time) { Time.now - 3600 }

      before do
        stub_history('XMR', 1, body: json({
          price: [
            [(time - 80).to_i * 1000, nil],
          ]
        }))
      end

      it 'should throw NoDataError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::NoDataError)
      end
    end

    context 'when status 400 is returned' do
      before do
        stub_history('XMR', 1, status: [400, 'Bad Request'])
      end

      it 'should throw BadRequestError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::BadRequestError, '400 Bad Request')
      end
    end

    context 'when status 5xx is returned' do
      before do
        stub_history('XMR', 1, status: [500, 'Internal Server Error'])
      end

      it 'should throw ServiceUnavailableError' do
        proc {
          subject.get_price('XMR', Time.now - 3600)
        }.should raise_error(CoinTools::ServiceUnavailableError, '500 Internal Server Error')
      end
    end
  end
end
