module CoinTools
  class Error < StandardError
    def nice_message
      "#{self.class}: #{message}"
    end
  end


  class UserError < Error
  end

  class InvalidDateError < UserError
  end

  class InvalidExchangeError < UserError
  end

  class InvalidFiatCurrencyError < UserError
  end

  class InvalidSymbolError < UserError
  end


  class ResponseError < Error
    attr_reader :response

    def initialize(response, message = nil)
      super(message || "#{response.code} #{response.message}")
      @response = response
    end
  end

  class JSONError < ResponseError
    def initialize(response, message = nil)
      super(response, message || "Incorrect JSON structure")
    end
  end

  class NoDataError < ResponseError
    def initialize(response, message = nil)
      super(response, message || "Missing data in the response")
    end
  end

  class BadRequestError < ResponseError
  end

  class UnknownCoinError < BadRequestError
  end

  class UnknownExchangeError < BadRequestError
  end

  class ServiceUnavailableError < ResponseError
  end
end
