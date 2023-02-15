defmodule Lightning.AuthProviders.GoogleTest do
  use ExUnit.Case, async: false
  import Lightning.BypassHelpers

  alias Lightning.AuthProviders.Google

  setup do
    bypass = Bypass.open()

    Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
      google: [wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known"]
    )

    expect_wellknown(bypass)

    {:ok, bypass: bypass, endpoint_url: "http://localhost:#{bypass.port}"}
  end

  describe "get_wellknown/0" do
    test "pulls the .well-known from the path specified in the Application" do
      assert %Lightning.AuthProviders.WellKnown{} = Google.get_wellknown()
    end
  end
end
