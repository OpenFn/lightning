defmodule Lightning.Invocation.RequestHeadersTest do
  use ExUnit.Case, async: true

  alias Lightning.Invocation.RequestHeaders
  alias Lightning.Workflows.WebhookAuthMethod

  defp api_method(api_key),
    do: %WebhookAuthMethod{auth_type: :api, api_key: api_key}

  defp basic_method(username, password),
    do: %WebhookAuthMethod{
      auth_type: :basic,
      username: username,
      password: password
    }

  describe "redact/2 with no auth methods on the trigger" do
    test "passes every header through except the two redacted by name" do
      headers =
        RequestHeaders.redact(
          [
            {"content-type", "application/json"},
            {"user-agent", "acme-integration/1.2"},
            {"x-api-key", "a-downstream-token"},
            {"authorization", "Bearer a-downstream-token"},
            {"cookie", "session=third-party-session"},
            {"proxy-authorization", "Basic cHJveHk6c2VjcmV0"}
          ],
          []
        )

      assert headers == %{
               "content-type" => "application/json",
               "user-agent" => "acme-integration/1.2",
               "x-api-key" => "a-downstream-token",
               "authorization" => "Bearer a-downstream-token",
               "cookie" => "[REDACTED]",
               "proxy-authorization" => "[REDACTED]"
             }
    end
  end

  describe "redact/2 with an api auth method" do
    test "redacts the api key Lightning authenticated with" do
      headers =
        RequestHeaders.redact(
          [{"x-api-key", "sup3r-s3cret"}, {"content-type", "application/json"}],
          [api_method("sup3r-s3cret")]
        )

      assert headers["x-api-key"] == "[REDACTED]"
      assert headers["content-type"] == "application/json"
    end

    test "leaves a caller's unrelated x-api-key alone" do
      headers =
        RequestHeaders.redact(
          [
            {"x-api-key", "ours-sup3r-s3cret"},
            {"x-downstream-api-key", "the-caller-forwards-this"}
          ],
          [api_method("ours-sup3r-s3cret")]
        )

      assert headers["x-api-key"] == "[REDACTED]"

      assert headers["x-downstream-api-key"] == "the-caller-forwards-this",
             "matching on value is the whole point: a token that is not ours " <>
               "must survive, or every job forwarding one breaks"
    end

    test "leaves a header we never read alone, even carrying our secret" do
      headers =
        RequestHeaders.redact(
          [{"x-custom-auth", "prefix ours-sup3r-s3cret suffix"}],
          [api_method("ours-sup3r-s3cret")]
        )

      assert headers["x-custom-auth"] == "prefix ours-sup3r-s3cret suffix",
             "what a caller puts in a header webhook auth does not read is " <>
               "theirs; rewriting it is not ours to do"
    end

    test "redacts our key from authorization when the caller sends it twice" do
      headers =
        RequestHeaders.redact(
          [
            {"x-api-key", "ours-sup3r-s3cret"},
            {"authorization", "Bearer ours-sup3r-s3cret"}
          ],
          [api_method("ours-sup3r-s3cret")]
        )

      assert headers["x-api-key"] == "[REDACTED]"

      assert headers["authorization"] == "Bearer [REDACTED]",
             "auth matched on x-api-key, but the copy in the other header we " <>
               "read would otherwise be persisted intact"
    end

    test "redacts our secret sent under an unexpected scheme" do
      headers =
        RequestHeaders.redact(
          [{"authorization", "Bearer ours-sup3r-s3cret"}],
          [api_method("ours-sup3r-s3cret")]
        )

      assert headers["authorization"] == "Bearer [REDACTED]"
    end

    test "handles several auth methods on one trigger" do
      headers =
        RequestHeaders.redact(
          [{"x-api-key", "second-key"}],
          [api_method("first-key"), api_method("second-key")]
        )

      assert headers["x-api-key"] == "[REDACTED]"
    end
  end

  describe "redact/2 with a basic auth method" do
    test "redacts the base64 credentials, keeping the scheme legible" do
      credentials = Base.encode64("caller:sup3r-s3cret-password")

      headers =
        RequestHeaders.redact(
          [{"authorization", "Basic #{credentials}"}],
          [basic_method("caller", "sup3r-s3cret-password")]
        )

      assert headers["authorization"] == "Basic [REDACTED]"
    end

    test "redacts the raw password when it arrives in a header we read" do
      headers =
        RequestHeaders.redact(
          [{"authorization", "sup3r-s3cret-password"}],
          [basic_method("caller", "sup3r-s3cret-password")]
        )

      assert headers["authorization"] == "[REDACTED]"
    end

    test "leaves the password alone in a header we do not read" do
      headers =
        RequestHeaders.redact(
          [{"x-password", "sup3r-s3cret-password"}],
          [basic_method("caller", "sup3r-s3cret-password")]
        )

      assert headers["x-password"] == "sup3r-s3cret-password"
    end

    test "leaves a caller's unrelated Basic credentials alone" do
      theirs = Base.encode64("someone:else")

      headers =
        RequestHeaders.redact(
          [{"authorization", "Basic #{theirs}"}],
          [basic_method("caller", "sup3r-s3cret-password")]
        )

      assert headers["authorization"] == "Basic #{theirs}"
    end
  end

  describe "redact/2 edge cases" do
    test "an auth method with no secret set scrubs nothing" do
      headers =
        RequestHeaders.redact(
          [{"x-api-key", "a-token"}],
          [%WebhookAuthMethod{auth_type: :api, api_key: nil}]
        )

      assert headers["x-api-key"] == "a-token",
             "an empty sample list must not turn into a match-everything"
    end

    test "header names are matched case insensitively for name redaction" do
      headers = RequestHeaders.redact([{"Cookie", "session=abc"}], [])

      assert headers["Cookie"] == "[REDACTED]"
    end

    test "duplicate header names collapse to the last, as Enum.into/2 did" do
      headers =
        RequestHeaders.redact([{"x-seq", "first"}, {"x-seq", "last"}], [])

      assert headers == %{"x-seq" => "last"}
    end

    test "raises rather than silently scrubbing nothing on an unloaded assoc" do
      assert_raise FunctionClauseError, fn ->
        RequestHeaders.redact(
          [{"x-api-key", "sup3r-s3cret"}],
          %Ecto.Association.NotLoaded{
            __field__: :webhook_auth_methods,
            __owner__: Lightning.Workflows.Trigger,
            __cardinality__: :many
          }
        )
      end
    end
  end
end
