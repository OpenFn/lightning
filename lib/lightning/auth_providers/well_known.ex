defmodule Lightning.AuthProviders.WellKnown do
  @moduledoc """
  A datastructure to fetch and hold information about a given OIDC/OAuth provider
  """
  use HTTPoison.Base

  @fields [
    :authorization_endpoint,
    :token_endpoint,
    :userinfo_endpoint,
    :introspection_endpoint
  ]

  defstruct @fields

  @type t :: %__MODULE__{
          authorization_endpoint: String.t(),
          token_endpoint: String.t(),
          userinfo_endpoint: String.t(),
          introspection_endpoint: String.t()
        }

  @spec fetch(discovery_url :: String.t()) ::
          {:ok, __MODULE__.t()} | {:error, reason :: term()}
  def fetch(discovery_url) do
    with {:ok, response} <- get(discovery_url),
         {:ok, decoded} <- Jason.decode(response.body) do
      {:ok, new(decoded)}
    end
  end

  @spec fetch!(discovery_url :: String.t()) ::
          __MODULE__.t()
  def fetch!(discovery_url) do
    with {:ok, response} <- get(discovery_url),
         {:ok, args} <- response.body |> Jason.decode() do
      new(args)
    end
  end

  @spec new(json_body :: %{String.t() => term()}) :: __MODULE__.t()
  def new(%{} = json_body) do
    struct!(
      __MODULE__,
      @fields
      |> Enum.map(fn key ->
        {key, json_body[key |> to_string()]}
      end)
    )
  end
end
