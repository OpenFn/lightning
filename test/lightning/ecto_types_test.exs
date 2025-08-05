defmodule Lightning.EctoTypesTest do
  use ExUnit.Case, async: true

  alias Lightning.LogMessage
  alias Lightning.UnixDateTime

  describe "LogMessage" do
    test "can be cast from a string" do
      assert {:ok, "Hello, world!"} = LogMessage.cast("Hello, world!")
    end

    test "can be cast from a list" do
      assert {:ok, ~s<Hello, world! {"foo":"bar"} null>} =
               LogMessage.cast(["Hello, world!", %{"foo" => "bar"}, nil])

      assert {:ok, ~s<null>} =
               LogMessage.cast([nil])
    end

    test "can be cast from a map" do
      assert {:ok, ~s<{"baz":null,"foo":"bar"}>} =
               LogMessage.cast(%{"foo" => "bar", "baz" => nil})
    end

    test "can be cast from an integer" do
      assert {:ok, ~s<12345>} =
               LogMessage.cast(12345)
    end

    test "can be cast from a float" do
      assert {:ok, ~s<5.893>} =
               LogMessage.cast(5.893)
    end

    test "can be cast from a boolean" do
      assert {:ok, ~s<true>} =
               LogMessage.cast(true)

      assert {:ok, ~s<false>} =
               LogMessage.cast(false)
    end

    test "sanitizes null bytes in strings" do
      assert {:ok, "Hello�World"} = LogMessage.cast("Hello\x00World")
      assert {:ok, "���"} = LogMessage.cast("\x00\x00\x00")
    end

    test "sanitizes control characters" do
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x01here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x02here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x03here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x04here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x05here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x06here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x07here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x08here")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x0Bhere")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x0Chere")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x0Ehere")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x0Fhere")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x1Fhere")
      assert {:ok, "Text�here"} = LogMessage.cast("Text\x7Fhere")
    end

    test "preserves valid control characters" do
      assert {:ok, "Text\there"} = LogMessage.cast("Text\there")
      assert {:ok, "Text\nhere"} = LogMessage.cast("Text\nhere")
      assert {:ok, "Text\rhere"} = LogMessage.cast("Text\rhere")
    end

    test "sanitizes null bytes in lists" do
      assert {:ok, "Hello �World Test"} =
               LogMessage.cast(["Hello", "\x00World", "Test"])
    end

    test "sanitizes null bytes in JSON maps" do
      input = %{"message" => "Error\x00here", "level" => "error"}
      {:ok, result} = LogMessage.cast(input)

      assert result =~ "Error�here"
      assert result =~ "error"
    end

    test "sanitizes when dumping to database" do
      assert {:ok, "Clean�text"} = LogMessage.dump("Clean\x00text")
    end

    test "handles mixed valid and invalid content" do
      input = "Valid text\x00with null\x01and control\x1Fchars\nand newlines"

      assert {:ok, "Valid text�with null�and control�chars\nand newlines"} =
               LogMessage.cast(input)
    end

    test "preserves unicode while sanitizing" do
      assert {:ok, "Hello 👋 �World 🌍"} = LogMessage.cast("Hello 👋 \x00World 🌍")
      assert {:ok, "Café�"} = LogMessage.cast("Café\x00")
      assert {:ok, "日本語�test"} = LogMessage.cast("日本語\x00test")
    end

    test "handles JSON encoding errors for maps" do
      invalid_map = %{key: {:tuple, "value"}}

      assert {:error, _} = LogMessage.cast(invalid_map)
    end

    test "handles cast errors in lists by converting to empty string" do
      list_with_invalid = [
        "valid string",
        fn x -> x end,
        "another valid string",
        {:tuple, "value"},
        123
      ]

      assert {:ok, "valid string  another valid string  123"} =
               LogMessage.cast(list_with_invalid)
    end

    test "handles lists with only invalid items" do
      invalid_list = [fn -> nil end, {:ok, :tuple}, self()]

      assert {:ok, "  "} = LogMessage.cast(invalid_list)
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
