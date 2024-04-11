defmodule Lightning.UsageTracking.ResponseProcessorTest do
  use ExUnit.Case

  alias Lightning.UsageTracking.ResponseProcessor

  describe ".successful?/1" do
    test "returns false with a status outside the 2xx range" do
      response = {:ok, %Tesla.Env{status: 199}}

      refute(ResponseProcessor.successful?(response))

      response = {:ok, %Tesla.Env{status: 300}}

      refute(ResponseProcessor.successful?(response))
    end

    test "returns true within the 2xx range" do
      response = {:ok, %Tesla.Env{status: 200}}

      assert(ResponseProcessor.successful?(response))

      response = {:ok, %Tesla.Env{status: 299}}

      assert(ResponseProcessor.successful?(response))
    end

    test "anything other than a Tesla.Env struct is considered unsuccessful" do
      refute(ResponseProcessor.successful?({:error, :nxdomain}))
      refute(ResponseProcessor.successful?({:error, :econnrefused}))
    end
  end

  describe ".successful_200?/1" do
    test "returns false with a status that is not 200" do
      response = {:ok, %Tesla.Env{status: 201}}

      assert ResponseProcessor.successful_200?(response) == false

      response = {:ok, %Tesla.Env{status: 400}}

      assert ResponseProcessor.successful_200?(response) == false
    end

    test "returns true for a 200 response" do
      response = {:ok, %Tesla.Env{status: 200}}

      assert(ResponseProcessor.successful_200?(response))
    end

    test "anything other than a Tesla.Env struct is considered unsuccessful" do
      assert ResponseProcessor.successful_200?({:error, :nxdomain}) == false
      assert ResponseProcessor.successful_200?({:error, :econnrefused}) == false
    end
  end
end
