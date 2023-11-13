defmodule Lightning.EctoTypesTest do
  use ExUnit.Case

  alias Lightning.LogMessage
  alias Lightning.UnixDateTime

  describe "LogMessage" do
    test "can be cast from a string" do
      assert {:ok, "Hello, world!"} = LogMessage.cast("Hello, world!")
    end

    test "can be cast from a list" do
      assert {:ok, ~s<Hello, world! {"foo":"bar"} null>} =
               LogMessage.cast(["Hello, world!", %{"foo" => "bar"}, nil])
    end

    test "can be cast from a map" do
      assert {:ok, ~s<{"baz":null,"foo":"bar"}>} =
               LogMessage.cast(%{"foo" => "bar", "baz" => nil})
    end
  end

  describe "UnixDateTime" do
    test "can be cast from a string" do
      timestamp = "1699867499906674"

      assert {:ok, ~U[2023-11-13 09:24:59.906674Z]} =
               UnixDateTime.cast(timestamp)

      timestamp = "1699867499906"

      assert {:ok, ~U[2023-11-13 09:24:59.906000Z]} =
               UnixDateTime.cast(timestamp)
    end

    test "raises an error when the string is invalid" do
      assert UnixDateTime.cast("invalid timestamp") == :error
    end
  end
end
