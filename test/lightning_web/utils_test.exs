defmodule LightningWeb.UtilsTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Utils

  describe "normalize_hex/1" do
    test "returns fallback for nil" do
      assert Utils.normalize_hex(nil) == "#79B2D6"
    end

    test "returns fallback for non-binary input" do
      assert Utils.normalize_hex(123) == "#79B2D6"
      assert Utils.normalize_hex(:blue) == "#79B2D6"
    end

    test "expands 3-digit shorthand (#RGB)" do
      assert Utils.normalize_hex("#abc") == "#AABBCC"
      assert Utils.normalize_hex("abc") == "#AABBCC"
      assert Utils.normalize_hex("ABC") == "#AABBCC"
    end

    test "handles 6-digit hex (#RRGGBB)" do
      assert Utils.normalize_hex("#A1B2C3") == "#A1B2C3"
      assert Utils.normalize_hex("a1b2c3") == "#A1B2C3"
    end

    test "handles 6+ digit input, truncating extras" do
      # Only first 6 chars should matter
      assert Utils.normalize_hex("1234567890") == "#123456"
      assert Utils.normalize_hex("#ABCDEF00") == "#ABCDEF"
    end

    test "trims whitespace and leading #" do
      assert Utils.normalize_hex("  #1a2b3c  ") == "#1A2B3C"
      assert Utils.normalize_hex("  1a2b3c") == "#1A2B3C"
    end

    test "returns fallback for invalid strings" do
      assert Utils.normalize_hex("") == "#79B2D6"
      assert Utils.normalize_hex("xy") == "#79B2D6"
      assert Utils.normalize_hex("zzzzzz") == "#79B2D6"
      assert Utils.normalize_hex("12") == "#79B2D6"
      assert Utils.normalize_hex("1234") == "#79B2D6"
    end
  end
end
