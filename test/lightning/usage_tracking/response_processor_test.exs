defmodule Lightning.UsageTracking.ResponseProcessorTest do
  use ExUnit.Case

  alias Lightning.UsageTracking.ResponseProcessor

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
end
