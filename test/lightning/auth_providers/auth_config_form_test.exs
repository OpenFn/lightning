defmodule Lightning.AuthProviders.AuthConfigFormTest do
  use ExUnit.Case, async: true

  alias Lightning.AuthProviders.AuthConfigForm

  describe "validate_provider/1" do
    test "adds a friendly error (rather than crashing) for an insecure discovery url" do
      changeset =
        AuthConfigForm.change(%AuthConfigForm{}, %{
          "name" => "provider",
          "discovery_url" => "http://accounts.example.com/.well-known",
          "client_id" => "id",
          "client_secret" => "secret",
          "redirect_uri" => "http://localhost/callback"
        })

      result = AuthConfigForm.validate_provider(changeset)

      assert {"discovery endpoint must use https", _} =
               result.errors[:discovery_url]
    end
  end
end
