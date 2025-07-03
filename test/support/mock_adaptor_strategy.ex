defmodule MockAdaptorStrategy do
  @moduledoc """
  Mock adaptor strategy for testing Lightning.Adaptors functionality.
  """
  
  @behaviour Lightning.Adaptors.Strategy

  @impl true
  def fetch_packages(_config) do
    {:ok, ["@openfn/language-foo", "@openfn/language-bar"]}
  end

  @impl true
  def fetch_versions(_config, package_name) do
    case package_name do
      "@openfn/language-foo" ->
        {:ok,
         %{
           "1.0.0" => %{"version" => "1.0.0"},
           "2.0.0" => %{"version" => "2.0.0"},
           "2.1.0" => %{"version" => "2.1.0"}
         }}

      "@openfn/language-bar" ->
        {:ok,
         %{
           "2.0.0" => %{"version" => "2.0.0"},
           "2.1.0" => %{"version" => "2.1.0"},
           "latest" => %{"version" => "2.1.0"}
         }}

      _ ->
        {:error, :not_found}
    end
  end

  @impl true
  def validate_config(_config), do: {:ok, []}

  @impl true
  def fetch_configuration_schema(_adaptor_name) do
    {:error, :not_implemented}
  end

  @impl true
  def fetch_icon(_adaptor_name, _version) do
    {:error, :not_implemented}
  end
end