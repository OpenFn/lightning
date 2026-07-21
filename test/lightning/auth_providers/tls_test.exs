defmodule Lightning.AuthProviders.TLSTest do
  use ExUnit.Case, async: false

  alias Lightning.AuthProviders.TLS

  describe "secure_url?/1" do
    test "accepts any https url" do
      assert TLS.secure_url?("https://accounts.example.com/.well-known")
    end

    test "rejects plaintext http on a non-loopback host" do
      refute TLS.secure_url?("http://accounts.example.com/.well-known")
    end

    test "treats a nil or blank url as insecure rather than crashing" do
      refute TLS.secure_url?(nil)
      refute TLS.secure_url?("")
    end

    test "accepts loopback http only when the insecure-loopback flag is set" do
      key = :auth_providers_allow_insecure_loopback
      original = Application.get_env(:lightning, key)
      on_exit(fn -> Application.put_env(:lightning, key, original) end)

      Application.put_env(:lightning, key, false)
      refute TLS.secure_url?("http://localhost:4000/.well-known")
      refute TLS.secure_url?("http://127.0.0.1:4000/.well-known")

      Application.put_env(:lightning, key, true)
      assert TLS.secure_url?("http://localhost:4000/.well-known")
      assert TLS.secure_url?("http://127.0.0.1:4000/.well-known")
    end
  end
end
