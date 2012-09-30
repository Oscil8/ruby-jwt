#
# JSON Web Signature implementation
#
# Should be up to date with the latest spec:
# http://tools.ietf.org/html/draft-ietf-jose-json-web-signature-05
# TODO: verify!

module JWS
  def self.sign(algorithm, msg, key)
    if ["HS256", "HS384", "HS512"].include?(algorithm)
      sign_hmac(algorithm, msg, key)
    elsif ["RS256", "RS384", "RS512"].include?(algorithm)
      sign_rsa(algorithm, msg, key)
    else
      raise NotImplementedError.new("Unsupported signing method")
    end
  end

  def self.sign_rsa(algorithm, msg, private_key)
    private_key.sign(OpenSSL::Digest::Digest.new(algorithm.sub('RS', 'sha')), msg)
  end

  def self.verify_rsa(algorithm, public_key, signing_input, signature)
    public_key.verify(OpenSSL::Digest::Digest.new(algorithm.sub('RS', 'sha')), signature, signing_input)
  end

  def self.sign_hmac(algorithm, msg, key)
    OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new(algorithm.sub('HS', 'sha')), key, msg)
  end

  def self.encode(payload, key, algorithm='HS256', header_fields={})
    algorithm ||= "none"
    segments = []
    header = {"typ" => "JWT", "alg" => algorithm}.merge(header_fields)
    segments << JWT.base64url_encode(MultiJson.encode(header))
    segments << JWT.base64url_encode(MultiJson.encode(payload))
    signing_input = segments.join('.')
    if algorithm != "none"
      signature = sign(algorithm, signing_input, key)
      segments << JWT.base64url_encode(signature)
    else
      segments << ""
    end
    segments.join('.')
  end

  def self.decode(jwt, key=nil, verify=true, &keyfinder)
    segments = jwt.split('.')
    raise JWT::DecodeError.new("Not enough or too many segments") unless [2,3].include? segments.length
    header_segment, payload_segment, crypto_segment = segments
    signing_input = [header_segment, payload_segment].join('.')
    begin
      header = MultiJson.decode(JWT.base64url_decode(header_segment))
      payload = MultiJson.decode(JWT.base64url_decode(payload_segment))
      signature = JWT.base64url_decode(crypto_segment) if verify
    rescue JSON::ParserError
      raise JWT::DecodeError.new("Invalid segment encoding")
    end
    # TODO: need to verify that set of header params is valid
    #    4.  The resulting JWS Header MUST be validated to only include
    #        parameters and values whose syntax and semantics are both
    #        understood and supported.
    if verify == true
      algo = header['alg']

      if keyfinder
        key = keyfinder.call(header)
      end

      begin
        if ["HS256", "HS384", "HS512"].include?(algo)
          raise JWT::DecodeError.new("Signature verification failed") unless signature == sign_hmac(algo, signing_input, key)
        elsif ["RS256", "RS384", "RS512"].include?(algo)
          raise JWT::DecodeError.new("Signature verification failed") unless verify_rsa(algo, key, signing_input, signature)
        else
          raise JWT::DecodeError.new("Algorithm not supported")
        end
      rescue OpenSSL::PKey::PKeyError
        raise JWT::DecodeError.new("Signature verification failed")
      end
    end
    payload
  end

end
