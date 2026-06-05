defmodule Lightning.AuthProviders.WellKnown do
  @moduledoc """
  A datastructure to fetch and hold information about a given OIDC/OAuth provider
  """
  use HTTPoison.Base

  @discovery_fields [
    :authorization_endpoint,
    :token_endpoint,
    :userinfo_endpoint,
    :introspection_endpoint
  ]

  # `:user_emails_endpoint` resolves a verified email for providers (e.g. GitHub) whose userinfo endpoint doesn't return one.
  defstruct @discovery_fields ++ [:user_emails_endpoint]

  @type t :: %__MODULE__{
          authorization_endpoint: String.t(),
          token_endpoint: String.t(),
          userinfo_endpoint: String.t(),
          introspection_endpoint: String.t(),
          user_emails_endpoint: String.t() | nil
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
      @discovery_fields
      |> Enum.map(fn key ->
        {key, json_body[key |> to_string()]}
      end)
    )
  end
end
