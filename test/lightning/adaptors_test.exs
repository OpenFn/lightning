defmodule MockAdaptorStrategy do
  @behaviour Lightning.Adaptors.Strategy
  def fetch_adaptors(_config) do
    {:ok,
     [
       %{
         name: "@openfn/language-foo",
         repo: "https://github.com/openfn/foo",
         latest: "1.0.0",
         versions: [%{version: "1.0.0"}]
       }
     ]}
  end

  def fetch_credential_schema(_adaptor_name, _version) do
    {:error, :not_implemented}
  end

  def fetch_icon(_adaptor_name, _version) do
    {:error, :not_implemented}
  end
end

defmodule Lightning.AdaptorsTest do
  use ExUnit.Case, async: true

  test "all/1" do
    start_supervised!({Cachex, [:adaptors_test, []]})

    assert Lightning.Adaptors.all(%{
             strategy: {MockAdaptorStrategy, [config: "foo"]},
             cache: :adaptors_test
           }) == []
  end
end
