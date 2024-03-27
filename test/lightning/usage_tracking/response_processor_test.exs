defmodule Lightning.UsageTracking.ResponseProcessorTest do
  use ExUnit.Case

  alias Lightning.UsageTracking.ResponseProcessor

  describe ".successful?/1" do
    test "returns false with a status outside the 2xx range" do
      env = %Tesla.Env{status: 199}

      refute(ResponseProcessor.successful?(env))

      env = %Tesla.Env{status: 300}

      refute(ResponseProcessor.successful?(env))
    end

    test "returns true within the 2xx range" do
      env = %Tesla.Env{status: 200}

      assert(ResponseProcessor.successful?(env))

      env = %Tesla.Env{status: 299}

      assert(ResponseProcessor.successful?(env))
    end

    test "anything other than a Tesla.Env struct is considered unsuccessful" do
      refute(ResponseProcessor.successful?(:nxdomain))
      refute(ResponseProcessor.successful?(:econnrefused))
    end
  end

  describe ".successful_200?/1" do
    test "returns false with a status that is not 200" do
      env = %Tesla.Env{status: 201}

      assert ResponseProcessor.successful_200?(env) == false

      env = %Tesla.Env{status: 400}

      assert ResponseProcessor.successful_200?(env) == false
    end

    test "returns true for a 200 response" do
      env = %Tesla.Env{status: 200}

      assert(ResponseProcessor.successful_200?(env))
    end

    test "anything other than a Tesla.Env struct is considered unsuccessful" do
      assert ResponseProcessor.successful_200?(:nxdomain) == false
      assert ResponseProcessor.successful_200?(:econnrefused) == false
    end
  end
end
