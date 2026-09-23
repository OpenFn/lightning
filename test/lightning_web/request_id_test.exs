defmodule LightningWeb.RequestIdTest do
  use ExUnit.Case, async: true

  alias LightningWeb.RequestId

  describe "parse/1" do
    test "accepts an id Plug.RequestId would generate" do
      id = "GNfmKvL6pUjAQ9IAABzB"
      assert RequestId.parse(%{"request_id" => id}) == id
    end

    test "rejects ids of the wrong length, bad characters, or wrong type" do
      for bad <- [
            "short",
            String.duplicate("a", 201),
            "GNfmKvL6pUjAQ9IAABzB\nforged log line",
            "GNfmKvL6pUjAQ9IAABzB<script>",
            123,
            nil
          ] do
        assert RequestId.parse(%{"request_id" => bad}) == nil, inspect(bad)
      end

      assert RequestId.parse(%{}) == nil
      assert RequestId.parse(nil) == nil
    end
  end
end
