defmodule Lightning.Validators.HexTest do
  use ExUnit.Case, async: true

  alias Lightning.Validators.Hex

  # Verify examples in the @moduledoc
  doctest Hex

  describe "valid?/3 – defaults" do
    test "defaults to 12 lowercase hex" do
      assert Hex.valid?("deadbeefcafe")
      refute Hex.valid?("DEADBEEFCAFE")
      # 11 chars
      refute Hex.valid?("deadbeefcaf")
      # 13 chars
      refute Hex.valid?("deadbeefcafe0")
      # 'g' is not hex
      refute Hex.valid?("deadbeefcagf")
    end

    test "returns false for non-binaries" do
      refute Hex.valid?(123)
      refute Hex.valid?(nil)
      refute Hex.valid?(~c['a', 'b'])
      refute Hex.valid?({:ok, "deadbeefcafe"})
    end
  end

  describe "valid?/3 – exact length" do
    test "lowercase required by default" do
      assert Hex.valid?("abc123ff", 8)
      refute Hex.valid?("ABC123FF", 8)
    end

    test "uppercase allowed with case: :upper" do
      assert Hex.valid?("ABC123FF", 8, case: :upper)
      # contains lowercase
      refute Hex.valid?("AbC123fF", 8, case: :upper)
    end

    test "mixed case allowed with case: :any" do
      assert Hex.valid?("AbC123fF", 8, case: :any)
    end

    test "unknown case option falls back to lowercase" do
      assert Hex.valid?("abc123ff", 8, case: :weird)
      refute Hex.valid?("ABC123FF", 8, case: :weird)
    end

    test "works with default length + options" do
      assert Hex.valid?("DEADBEEFCAFE", case: :upper)
      assert Hex.valid?("DeadBeefCafe", case: :any)
      refute Hex.valid?("DeadBeefCafe", case: :lower)
    end
  end

  describe "valid?/3 – range length" do
    test "inclusive min..max" do
      assert Hex.valid?("a", 1..2)
      assert Hex.valid?("ab", 1..2)
      refute Hex.valid?("", 1..2)
      refute Hex.valid?("abc", 1..2)
    end
  end

  describe "format/2 – regex builder" do
    test "default pattern is 12 lowercase hex" do
      r = Hex.format()
      assert is_struct(r, Regex)
      assert Regex.source(r) == "^[0-9a-f]{12}$"
      assert Regex.match?(r, "deadbeefcafe")
      refute Regex.match?(r, "DEADBEEFCAFE")
    end

    test "custom exact length and case" do
      r = Hex.format(8)
      assert Regex.source(r) == "^[0-9a-f]{8}$"

      r_upper = Hex.format(8, case: :upper)
      assert Regex.source(r_upper) == "^[0-9A-F]{8}$"

      r_any = Hex.format(8, case: :any)
      assert Regex.source(r_any) == "^[0-9A-Fa-f]{8}$"
    end

    test "length range and case" do
      r = Hex.format(8..64, case: :any)
      assert Regex.source(r) == "^[0-9A-Fa-f]{8,64}$"
      assert Regex.match?(r, "a" |> String.duplicate(8))
      assert Regex.match?(r, "A" |> String.duplicate(64))
      refute Regex.match?(r, "a" |> String.duplicate(7))
      refute Regex.match?(r, "a" |> String.duplicate(65))
    end
  end

  describe "format/2 – invalid length_spec raises" do
    test "zero or negative integers" do
      assert_raise ArgumentError, ~r/invalid length_spec/, fn ->
        Hex.format(0)
      end

      assert_raise ArgumentError, ~r/invalid length_spec/, fn ->
        Hex.format(-5)
      end
    end

    test "bad ranges: non-positive min, reversed, or stepped" do
      assert_raise ArgumentError, ~r/invalid length_spec/, fn ->
        Hex.format(0..2)
      end

      assert_raise ArgumentError, ~r/invalid length_spec/, fn ->
        Hex.format(5..3//-1)
      end

      assert_raise ArgumentError, ~r/invalid length_spec/, fn ->
        Hex.format(1..4//2)
      end
    end

    test "format/2 with unknown case falls back to lowercase" do
      r = Hex.format(4, case: :weird)
      assert Regex.source(r) == "^[0-9a-f]{4}$"
      assert Regex.match?(r, "abcd")
      refute Regex.match?(r, "ABCD")
    end
  end
end
