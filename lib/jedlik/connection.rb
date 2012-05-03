module Jedlik
  # Establishes a connection to Amazon DynamoDB using credentials.
  class Connection
    DEFAULTS = {
      :endpoint => 'dynamodb.us-east-1.amazonaws.com',
    }

    # Acceptable `opts` keys are:
    #
    #     :endpoint # DynamoDB endpoint to use.
    #               # Default: 'dynamodb.us-east-1.amazonaws.com'
    #
    def initialize(opts = {})
      opts = DEFAULTS.merge opts

      if opts[:token_service]
        @sts = opts[:token_service]
      elsif opts[:access_key_id] && opts[:secret_access_key]
        @sts = SecurityTokenService.new(opts[:access_key_id], opts[:secret_access_key])
      else
        raise ArgumentError.new("access_key_id and secret_access_key are required")
      end

      @endpoint = opts[:endpoint]
    end

    # Create and send a request to DynamoDB.
    # Returns a hash extracted from the response body.
    #
    # `operation` can be any DynamoDB operation. `data` is a hash that will be
    # used as the request body (in JSON format). More info available at:
    #
    # http://docs.amazonwebservices.com/amazondynamodb/latest/developerguide
    #
    def post(operation, data={})
      credentials = @sts.credentials

      request = new_request(credentials, operation, Yajl::Encoder.encode(data))
      request.sign(credentials)

      hydra.queue(request)
      hydra.run
      response = request.response

      if response.code == 200
        case operation
        when :Query, :Scan, :GetItem
          Jedlik::Response.new(response)
        else
          Yajl::Parser.parse(response.body)
        end
      else
        raise_error(response)
      end
    end

    private

    def hydra
      Typhoeus::Hydra.hydra
    end

    def new_request(credentials, operation, body)
      Typhoeus::Request.new "https://#{@endpoint}/",
        :method   => :post,
        :body     => body,
        :headers  => {
          'host'                  => @endpoint,
          'content-type'          => "application/x-amz-json-1.0",
          'x-amz-date'            => (Time.now.utc.strftime "%a, %d %b %Y %H:%M:%S GMT"),
          'x-amz-security-token'  => credentials.session_token,
          'x-amz-target'          => "DynamoDB_20111205.#{operation}",
        }
    end

    def raise_error(response)
      case response.code
      when 400..499
        raise ClientError, response.body
      when 500..599
        raise ServerError, response.code
      else
        raise Exception, response.body
      end
    end
  end
end
