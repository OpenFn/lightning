defmodule LightningWeb.ChannelRequestLive.HelpersTest do
  use ExUnit.Case, async: true

  alias LightningWeb.ChannelRequestLive.Helpers

  describe "humanize_error/1" do
    test "maps transport error codes to human messages" do
      assert Helpers.humanize_error("nxdomain") =~
               "DNS lookup failed"

      assert Helpers.humanize_error("econnrefused") =~
               "Connection refused"

      assert Helpers.humanize_error("ehostunreach") =~
               "Host unreachable"

      assert Helpers.humanize_error("enetunreach") =~
               "Network unreachable"

      assert Helpers.humanize_error("closed") =~
               "Connection closed unexpectedly"

      assert Helpers.humanize_error("econnreset") =~
               "Connection reset"

      assert Helpers.humanize_error("econnaborted") =~
               "Connection aborted"

      assert Helpers.humanize_error("epipe") =~
               "Broken pipe"

      assert Helpers.humanize_error("connect_timeout") =~
               "Connection timed out"

      assert Helpers.humanize_error("response_timeout") =~
               "Response timed out"

      assert Helpers.humanize_error("timeout") =~
               "Request timed out"
    end

    test "maps credential error codes to human messages" do
      assert Helpers.humanize_error("credential_missing_auth_fields") =~
               "missing required authentication fields"

      assert Helpers.humanize_error("credential_environment_not_found") =~
               "credential environment could not be found"

      assert Helpers.humanize_error("oauth_refresh_failed") =~
               "OAuth token refresh failed"

      assert Helpers.humanize_error("oauth_reauthorization_required") =~
               "OAuth credential needs to be re-authorized"
    end

    test "handles unsupported_credential_schema with dynamic name" do
      result =
        Helpers.humanize_error("unsupported_credential_schema:my_schema")

      assert result =~ "Unsupported credential type"
      assert result =~ "my_schema"
    end

    test "passes through unknown error codes unchanged" do
      assert Helpers.humanize_error("some_unknown_error") ==
               "some_unknown_error"
    end
  end

  describe "error_category/1" do
    test "classifies transport errors" do
      for code <- ~w(nxdomain econnrefused ehostunreach enetunreach closed
                      econnreset econnaborted epipe connect_timeout
                      response_timeout timeout) do
        assert Helpers.error_category(code) == :transport,
               "expected #{code} to be :transport"
      end
    end

    test "classifies credential errors" do
      for code <- ~w(credential_missing_auth_fields
                      credential_environment_not_found
                      oauth_refresh_failed
                      oauth_reauthorization_required) do
        assert Helpers.error_category(code) == :credential,
               "expected #{code} to be :credential"
      end

      assert Helpers.error_category("unsupported_credential_schema:foo") ==
               :credential
    end

    test "returns nil for unknown error codes" do
      assert Helpers.error_category("something_else") == nil
    end
  end
end
