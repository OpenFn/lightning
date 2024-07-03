defmodule Lightning.AuthProviders.OAuthBehaviour do
  @moduledoc """
  Defines a behaviour for OAuth providers within the Lightning application,
  specifying a common interface for OAuth operations.
  This interface ensures consistency and interoperability among different
  authentication providers (e.g., Google, Salesforce)
  by defining a set of required functions that each provider must implement.
  """
  @callback get_token(
              client :: map(),
              wellknown_url :: String.t() | nil,
              params :: map()
            ) ::
              {:ok, map()} | {:error, map()}
  @callback refresh_token(
              client :: map(),
              token :: map(),
              wellknown_url :: String.t() | nil
            ) ::
              {:ok, map()} | {:error, map()}
  @callback refresh_token(
              token :: map(),
              wellknown_url :: String.t() | nil
            ) ::
              {:ok, map()} | {:error, map()}
  @callback get_userinfo(
              client :: map(),
              token :: map(),
              wellknown_url :: String.t()
            ) ::
              {:ok, map()} | {:error, map()}
  @callback build_client(opts :: Keyword.t()) ::
              {:ok, map()} | {:error, :invalid_config}
  @callback authorize_url(
              client :: map(),
              state :: String.t(),
              scopes :: list(String.t()),
              opts :: Keyword.t()
            ) :: String.t()
end
