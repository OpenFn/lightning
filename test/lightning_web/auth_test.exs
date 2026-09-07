defmodule LightningWeb.AuthTest do
  use ExUnit.Case, async: true

  alias LightningWeb.Auth
  alias Lightning.Workflows.WebhookAuthMethod

  import Plug.Test, only: [conn: 2]

  defp api_method(key) do
    %WebhookAuthMethod{auth_type: :api, api_key: key}
  end

  defp basic_method(username, password) do
    %WebhookAuthMethod{auth_type: :basic, username: username, password: password}
  end

  defp with_header(conn, key, value) do
    Plug.Conn.put_req_header(conn, key, value)
  end

  describe "valid_key?/2" do
    test "returns true for correct API key" do
      conn = conn(:get, "/") |> with_header("x-api-key", "my-secret")

      assert Auth.valid_key?(conn, [api_method("my-secret")])
    end

    test "returns false for wrong API key" do
      conn = conn(:get, "/") |> with_header("x-api-key", "wrong")

      refute Auth.valid_key?(conn, [api_method("my-secret")])
    end

    test "returns false when no x-api-key header" do
      conn = conn(:get, "/")

      refute Auth.valid_key?(conn, [api_method("my-secret")])
    end

    test "ignores non-api auth methods" do
      conn = conn(:get, "/") |> with_header("x-api-key", "anything")

      refute Auth.valid_key?(conn, [basic_method("user", "pass")])
    end

    test "matches any of multiple API key methods" do
      conn = conn(:get, "/") |> with_header("x-api-key", "key-2")

      assert Auth.valid_key?(conn, [
               api_method("key-1"),
               api_method("key-2")
             ])
    end
  end

  describe "valid_user?/2" do
    test "returns true for correct Basic Auth credentials" do
      encoded = Base.encode64("admin:secret123")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      assert Auth.valid_user?(conn, [basic_method("admin", "secret123")])
    end

    test "returns false for wrong credentials" do
      encoded = Base.encode64("admin:wrong")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      refute Auth.valid_user?(conn, [basic_method("admin", "secret123")])
    end

    test "returns false for wrong username" do
      encoded = Base.encode64("notadmin:secret123")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      refute Auth.valid_user?(conn, [basic_method("admin", "secret123")])
    end

    test "returns false when no authorization header" do
      conn = conn(:get, "/")

      refute Auth.valid_user?(conn, [basic_method("admin", "pass")])
    end

    test "returns false for malformed Authorization header" do
      conn =
        conn(:get, "/") |> with_header("authorization", "Basic !!!notbase64")

      refute Auth.valid_user?(conn, [basic_method("admin", "pass")])
    end

    test "returns false for non-Basic scheme" do
      conn = conn(:get, "/") |> with_header("authorization", "Bearer token123")

      refute Auth.valid_user?(conn, [basic_method("admin", "pass")])
    end

    test "ignores non-basic auth methods" do
      encoded = Base.encode64("admin:pass")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      refute Auth.valid_user?(conn, [api_method("some-key")])
    end

    test "matches any of multiple basic methods" do
      encoded = Base.encode64("user2:pass2")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      assert Auth.valid_user?(conn, [
               basic_method("user1", "pass1"),
               basic_method("user2", "pass2")
             ])
    end
  end

  describe "has_credentials?/1" do
    test "detects x-api-key header" do
      conn = conn(:get, "/") |> with_header("x-api-key", "anything")

      assert Auth.has_credentials?(conn)
    end

    test "detects authorization header" do
      conn = conn(:get, "/") |> with_header("authorization", "Basic abc")

      assert Auth.has_credentials?(conn)
    end

    test "returns false when no auth headers present" do
      conn = conn(:get, "/")

      refute Auth.has_credentials?(conn)
    end
  end

  describe "auth methods scheduled for deletion" do
    setup do
      %{revoked_at: DateTime.utc_now() |> Timex.shift(days: 7)}
    end

    test "valid_key? rejects a revoked API key", %{revoked_at: revoked_at} do
      conn = conn(:get, "/") |> with_header("x-api-key", "my-secret")

      revoked = %{api_method("my-secret") | scheduled_deletion: revoked_at}

      refute Auth.valid_key?(conn, [revoked])
    end

    test "valid_key? still accepts a live key alongside a revoked one", %{
      revoked_at: revoked_at
    } do
      conn = conn(:get, "/") |> with_header("x-api-key", "live-key")

      revoked = %{api_method("revoked-key") | scheduled_deletion: revoked_at}

      assert Auth.valid_key?(conn, [revoked, api_method("live-key")])
    end

    test "valid_user? rejects revoked basic credentials", %{
      revoked_at: revoked_at
    } do
      encoded = Base.encode64("admin:secret123")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      revoked = %{
        basic_method("admin", "secret123")
        | scheduled_deletion: revoked_at
      }

      refute Auth.valid_user?(conn, [revoked])
    end
  end
end
