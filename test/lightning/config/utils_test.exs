defmodule Lightning.Config.UtilsTest do
  use ExUnit.Case, async: true

  alias Lightning.Config.Utils

  describe "parse_host_list/1" do
    test "parses a single host" do
      assert Utils.parse_host_list("example.com") == ["example.com"]
    end

    test "parses a comma-separated list" do
      assert Utils.parse_host_list("example.com,internal.svc,api.example.org") ==
               ["example.com", "internal.svc", "api.example.org"]
    end

    test "normalises case and strips a single trailing dot" do
      assert Utils.parse_host_list("Example.COM.,Internal.Svc") ==
               ["example.com", "internal.svc"]
    end

    test "trims surrounding whitespace on each entry" do
      assert Utils.parse_host_list("  example.com ,\tinternal.svc  ") ==
               ["example.com", "internal.svc"]
    end

    test "leaves colon-bearing forms (port/IPv6 literal) untouched" do
      assert Utils.parse_host_list("example.com:8080,[::1]") ==
               ["example.com:8080", "[::1]"]
    end

    test "empty or whitespace-only input returns an empty list" do
      assert Utils.parse_host_list("") == []
      assert Utils.parse_host_list("   ") == []
      assert Utils.parse_host_list("\t \n") == []
    end

    test "raises naming the offending entry for a scheme" do
      assert_raise ArgumentError, ~r/https:\/\/example\.com/, fn ->
        Utils.parse_host_list("https://example.com")
      end
    end

    test "raises naming the offending entry for a path" do
      assert_raise ArgumentError, ~r|example\.com/api|, fn ->
        Utils.parse_host_list("example.com/api")
      end
    end

    test "raises naming the offending entry for internal whitespace" do
      assert_raise ArgumentError, ~r/example\.com bad/, fn ->
        Utils.parse_host_list("example.com bad")
      end
    end

    test "raises naming the offending entry for an @ character" do
      assert_raise ArgumentError, ~r/user@example\.com/, fn ->
        Utils.parse_host_list("user@example.com")
      end
    end

    test "raises for an empty segment between commas" do
      assert_raise ArgumentError, fn ->
        Utils.parse_host_list("example.com, ,internal.svc")
      end
    end

    test "names every offending entry when several are malformed" do
      error =
        assert_raise ArgumentError, fn ->
          Utils.parse_host_list("good.example,https://bad.one,user@bad.two")
        end

      assert error.message =~ "https://bad.one"
      assert error.message =~ "user@bad.two"
    end
  end
end
