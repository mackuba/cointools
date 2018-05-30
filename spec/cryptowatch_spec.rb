require 'spec_helper'

describe CoinTools::Cryptowatch do
  subject { CoinTools::Cryptowatch.new }

  let(:exchanges_url) { "https://api.cryptowat.ch/exchanges" }

  def markets_url(exchange)
    "https://api.cryptowat.ch/markets/#{exchange}"
  end

  def ticker_url(exchange, pair)
    "https://api.cryptowat.ch/markets/#{exchange}/#{pair}/price"
  end

  def ohlc_url(exchange, pair)
    "https://api.cryptowat.ch/markets/#{exchange}/#{pair}/ohlc"
  end

  def stub(exchange, pair, params)
    stub_request(:get, ticker_url(exchange, pair)).to_return(params)
  end

  def stub_history(exchange, pair, time, periods, data = nil)
    if data.nil?
      data = periods
      periods = nil
    end

    url = ohlc_url(exchange, pair) + "?after=#{time.to_i}"

    if periods
      url += "&periods=#{periods}"
    end

    stub_request(:get, url).to_return(body: json(
      data.merge(allowance: { cost: 50, remaining: 800 })
    ))
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

  describe '#get_markets' do
    context 'when a correct response is returned' do
      before do
        stub_request(:get, markets_url('bitfinex')).to_return(body: json({
          result: [
            { id: 1, pair: 'btcusd', active: true },
            { id: 2, pair: 'ltcusd', active: true },
            { id: 3, pair: 'xmrusd', active: false },
            { id: 4, pair: 'btceur', active: true },
            { id: 5, pair: 'ltceur', active: true },
          ]
        }))
      end

      it 'should return sorted symbols of active markets' do
        list = subject.get_markets('bitfinex')

        list.should == ['btceur', 'btcusd', 'ltceur', 'ltcusd']
      end
    end

    it 'should send user agent headers' do
      stub_request(:get, markets_url('bitfinex')).to_return(body: json({ result: [] }))

      subject.get_markets('bitfinex')

      WebMock.should have_requested(:get, markets_url('bitfinex')).with(headers: user_agent_header)
    end

    context 'when an invalid response is returned' do
      before do
        stub_request(:get, markets_url('bitfinex')).to_return(status: [500, 'Internal Server Error'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_markets('bitfinex')
        }.should raise_error(CoinTools::Cryptowatch::InvalidResponseException, '500 Internal Server Error')
      end
    end
  end

  describe '#get_current_price' do
    context 'when a correct response is returned' do
      before do
        stub('kraken', 'btceur', body: json({ result: { price: 6000.0 }, allowance: { cost: 10, remaining: 1000 }}))
      end

      it 'should return current price' do
        data = subject.get_current_price('kraken', 'btceur')
        data.price.should == 6000.0
      end

      it 'should return nil timestamp' do
        data = subject.get_current_price('kraken', 'btceur')
        data.time.should be_nil
      end

      it 'should return info about API usage' do
        data = subject.get_current_price('kraken', 'btceur')
        data.api_time_spent == 10
        data.api_time_remaining == 1000
      end
    end

    it 'should send user agent headers' do
      stub('bitstamp', 'btcusd', body: json({ result: {}, allowance: {}}))

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

  shared_examples 'get_price behavior' do |method, periods|
    context 'when time is nil' do
      it 'should forward the request to get_current_price' do
        subject.should_receive(:get_current_price).with('bitfinex', 'ltcusd').and_return(500.0)

        subject.send(method, 'bitfinex', 'ltcusd', nil).should == 500.0
      end
    end

    context 'when time is not set' do
      it 'should forward the request to get_current_price' do
        subject.should_receive(:get_current_price).with('bitfinex', 'ltcusd').and_return(300.0)

        subject.send(method, 'bitfinex', 'ltcusd').should == 300.0
      end
    end

    context 'when date is too far in the past' do
      it 'should throw InvalidDateException' do
        proc {
          subject.send(method, 'bitfinex', 'ltcusd', Time.new(2004, 5, 1))
        }.should raise_error(CoinTools::Cryptowatch::InvalidDateException)
      end
    end

    context 'when a future date is passed' do
      it 'should throw InvalidDateException' do
        proc {
          subject.send(method, 'bitfinex', 'ltcusd', Time.now + 86400)
        }.should raise_error(CoinTools::Cryptowatch::InvalidDateException)
      end
    end

    context 'when a correct response is returned' do
      let(:timestamp) { Time.now.to_i - 86400 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, {
          result: {
            "60": [
              [timestamp - 300, 400, 440, 420, 434, 0],
              [timestamp - 60, 435, 440, 426, 438, 0],
              [timestamp + 120, 438, 450, 432, 444, 0],
            ],
            "3600": [
              [timestamp - 3600, 390, 420, 390, 411, 0],
              [timestamp + 3600, 430, 440, 428, 436, 0],
            ],
          },
          allowance: { cost: 50, remaining: 800 }
        })
      end

      it 'should return opening price and timestamp closest to the requested time' do
        data = subject.send(method, 'gdax', 'ethusd', time)
        data.price.should == 435
        data.time.should == time - 60
      end

      it 'should return info about API usage' do
        data = subject.send(method, 'gdax', 'ethusd', time)
        data.api_time_spent == 50
        data.api_time_remaining == 800
      end
    end

    context 'if the closest point to the requested time is after that time' do
      let(:timestamp) { Time.now.to_i - 86400 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {
          "60": [
            [timestamp - 300, 400, 440, 420, 434, 0],
            [timestamp - 180, 435, 440, 426, 438, 0],
            [timestamp + 120, 438, 450, 432, 444, 0],
          ],
        })
      end

      it 'should return it' do
        data = subject.send(method, 'gdax', 'ethusd', time)
        data.price.should == 438
        data.time.should == time + 120
      end
    end

    context 'if all returned data points are before the requested time' do
      let(:timestamp) { Time.now.to_i - 86400 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {
          "60": [
            [timestamp - 300, 400, 440, 420, 434, 0],
            [timestamp - 60, 435, 440, 426, 438, 0],
            [timestamp - 30, 429, 438, 428, 432, 0],
          ],
          "3600": [
            [timestamp - 3600, 390, 420, 390, 411, 0],
          ],
        })
      end

      it 'should return opening price and timestamp closest to the requested time' do
        data = subject.send(method, 'gdax', 'ethusd', time)
        data.price.should == 429
        data.time.should == time - 30
      end
    end

    context 'if all returned data points are after the requested time' do
      let(:timestamp) { Time.now.to_i - 86400 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {
          "3600": [
            [timestamp + 14400, 430, 440, 428, 436, 0],
            [timestamp + 18000, 440, 450, 440, 448, 0],
          ],
          "7200": [
            [timestamp + 7200, 420, 439, 418, 435, 0],
            [timestamp + 14400, 435, 444, 434, 442, 0],
          ],
        })
      end

      it 'should return opening price and timestamp closest to the requested time' do
        data = subject.send(method, 'gdax', 'ethusd', time)
        data.price.should == 420
        data.time.should == time + 7200
      end
    end

    context 'if some data points have times in the future' do
      let(:timestamp) { Time.now.to_i - 60 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {
          "60": [
            [timestamp - 300, 400, 440, 420, 434, 0],
            [timestamp + 120, 438, 450, 432, 444, 0],
          ],
        })
      end

      it 'should should only take into account the points before current time' do
        data = subject.send(method, 'gdax', 'ethusd', time)
        data.price.should == 400
        data.time.should == time - 300
      end
    end

    context 'if all returned data points are in the future' do
      let(:timestamp) { Time.now.to_i - 3600 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {
          "3600": [
            [timestamp + 14400, 430, 440, 428, 436, 0],
            [timestamp + 18000, 440, 450, 440, 448, 0],
          ],
          "7200": [
            [timestamp + 7200, 420, 439, 418, 435, 0],
            [timestamp + 14400, 435, 444, 434, 442, 0],
          ],
        })
      end

      it 'should throw NoDataException' do
        proc {
          subject.send(method, 'gdax', 'ethusd', time)
        }.should raise_error(CoinTools::Cryptowatch::NoDataException)
      end
    end

    context 'if some data ranges are empty' do
      let(:timestamp) { Time.now.to_i - 86400 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {
          "60": [],
          "3600": [
            [timestamp + 14400, 430, 440, 428, 436, 0],
            [timestamp + 18000, 440, 450, 440, 448, 0],
          ],
          "7200": [],
        })
      end

      it 'should ignore them' do
        data = subject.send(method, 'gdax', 'ethusd', time)
        data.price.should == 430
        data.time.should == time + 14400
      end
    end

    context 'if no data points are returned' do
      let(:timestamp) { Time.now.to_i - 3600 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {
          "3600": [],
          "7200": [],
        })
      end

      it 'should throw NoDataException' do
        proc {
          subject.send(method, 'gdax', 'ethusd', time)
        }.should raise_error(CoinTools::Cryptowatch::NoDataException)
      end
    end

    context 'if no data is returned at all' do
      let(:timestamp) { Time.now.to_i - 3600 }
      let(:time) { Time.at(timestamp) }

      before do
        stub_history('gdax', 'ethusd', timestamp, periods, result: {})
      end

      it 'should throw NoDataException' do
        proc {
          subject.send(method, 'gdax', 'ethusd', time)
        }.should raise_error(CoinTools::Cryptowatch::NoDataException)
      end
    end
  end

  describe '#get_price' do
    include_examples 'get_price behavior', :get_price, nil

    it 'should send user agent headers' do
      time = Time.now - 300

      stub_history('gdax', 'ethusd', time, result: {
        "60": [[time.to_i, 400, 440, 420, 434, 0]],
      })

      subject.get_price('gdax', 'ethusd', time)

      WebMock.should have_requested(:get, ohlc_url('gdax', 'ethusd') + "?after=#{time.to_i}").with(
        headers: user_agent_header
      )
    end

    context 'when status 400 is returned' do
      let(:time) { Time.now - 300 }

      before do
        stub_request(:get, ohlc_url('gdax', 'ethusd') + "?after=#{time.to_i}").to_return(status: [400, 'Bad Request'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_price('gdax', 'ethusd', time)
        }.should raise_error(CoinTools::Cryptowatch::BadRequestException, '400 Bad Request')
      end
    end

    context 'when an invalid response is returned' do
      let(:time) { Time.now - 300 }

      before do
        stub_request(:get, ohlc_url('gdax', 'ethusd') + "?after=#{time.to_i}").to_return(status: [500, 'Server Error'])
      end

      it 'should throw an exception' do
        proc {
          subject.get_price('gdax', 'ethusd', time)
        }.should raise_error(CoinTools::Cryptowatch::InvalidResponseException, '500 Server Error')
      end
    end
  end

  describe '#get_price_fast' do
    let(:some_result) {{
      result: {
        "86400": [[Time.new(2013, 1, 1).to_i, 1.0, 1.1, 1.0, 1.02, 0]]
      },
      allowance: { cost: 50, remaining: 800 }
    }}

    include_examples 'get_price behavior', :get_price_fast, '60'

    it 'should send user agent headers' do
      time = Time.now - 300

      stub_request(:get, ohlc_url('gdax', 'ethusd')).with(query: hash_including({})).to_return(body: json(some_result))

      subject.get_price_fast('gdax', 'ethusd', time)

      WebMock.should have_requested(:get, ohlc_url('gdax', 'ethusd')).with(
        query: hash_including({}),
        headers: user_agent_header
      )
    end

    context 'when the date is more than 4 years ago' do
      let(:time) { Time.now - 86400 * 365 * 4.5 }

      it 'should forward the request to get_price' do
        subject.should_receive(:get_price).with('gdax', 'ethusd', time).and_return(10.0)

        subject.get_price_fast('gdax', 'ethusd', time).should == 10.0
      end
    end

    context 'when the date is less than 4 years ago' do
      let(:time) { Time.now - 86400 * 365 * 3.9 }

      it 'should load the 1-day data range' do
        stub_history('gdax', 'ethusd', time, '86400', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 3 years ago' do
      let(:time) { Time.now - 86400 * 365 * 2.5 }

      it 'should load the 12-hour data range' do
        stub_history('gdax', 'ethusd', time, '43200', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 2 years ago' do
      let(:time) { Time.now - 86400 * 700 }

      it 'should load the 6-hour data range' do
        stub_history('gdax', 'ethusd', time, '21600', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 1.5 years ago' do
      let(:time) { Time.now - 86400 * 500 }

      it 'should load the 4-hour data range' do
        stub_history('gdax', 'ethusd', time, '14400', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than a year ago' do
      let(:time) { Time.now - 86400 * 340 }

      it 'should load the 2-hour data range' do
        stub_history('gdax', 'ethusd', time, '7200', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 8 months ago' do
      let(:time) { Time.now - 86400 * 205 }

      it 'should load the 1-hour data range' do
        stub_history('gdax', 'ethusd', time, '3600', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 4 months ago' do
      let(:time) { Time.now - 86400 * 110 }

      it 'should load the 30-min data range' do
        stub_history('gdax', 'ethusd', time, '1800', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 2 months ago' do
      let(:time) { Time.now - 86400 * 58 }

      it 'should load the 15-min data range' do
        stub_history('gdax', 'ethusd', time, '900', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 15 days ago' do
      let(:time) { Time.now - 86400 * 14 }

      it 'should load the 5-min data range' do
        stub_history('gdax', 'ethusd', time, '300', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 10 days ago' do
      let(:time) { Time.now - 86400 * 9 }

      it 'should load the 3-min data range' do
        stub_history('gdax', 'ethusd', time, '180', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when the date is less than 3 days ago' do
      let(:time) { Time.now - 86400 * 2.8 }

      it 'should load the 1-min data range' do
        stub_history('gdax', 'ethusd', time, '60', some_result)

        proc { subject.get_price_fast('gdax', 'ethusd', time) }.should_not raise_error
      end
    end

    context 'when status 400 is returned' do
      let(:time) { Time.now - 300 }

      before do
        stub_request(:get, ohlc_url('gdax', 'ethusd') + "?after=#{time.to_i}&periods=60").to_return(
          status: [400, 'Bad Request']
        )
      end

      it 'should throw an exception' do
        proc {
          subject.get_price_fast('gdax', 'ethusd', time)
        }.should raise_error(CoinTools::Cryptowatch::BadRequestException, '400 Bad Request')
      end
    end

    context 'when an invalid response is returned' do
      let(:time) { Time.now - 300 }

      before do
        stub_request(:get, ohlc_url('gdax', 'ethusd') + "?after=#{time.to_i}&periods=60").to_return(
          status: [500, 'Server Error']
        )
      end

      it 'should throw an exception' do
        proc {
          subject.get_price_fast('gdax', 'ethusd', time)
        }.should raise_error(CoinTools::Cryptowatch::InvalidResponseException, '500 Server Error')
      end
    end
  end
end
