defmodule LightningWeb.API.CredentialSchemaController do
  @moduledoc """
  The credential types a credential's `schema` can name, and the JSON Schema
  each checks a body against.

      GET /api/credential_schemas
      GET /api/credential_schemas/:name

  A type's name is its adaptor's package name, so a client encodes the `/` in
  the path. A short name such as `dhis2` is accepted and answered under the
  full one. Both answer 503 `not_ready` while the adaptor catalogue can't.
  """
  use LightningWeb, :controller

  alias Lightning.Adaptors.PackageName
  alias Lightning.Credentials
  alias LightningWeb.API.FallbackController
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  plug AuthorizeAction,
       {:credentials, :read_credential_schemas}
       when action in [:index, :show]

  @spec index(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def index(conn, _params) do
    with {:ok, names} <- Credentials.list_schema_names() do
      json(conn, %{data: Enum.map(names, &%{name: &1, title: title(&1)})})
    end
  end

  @doc """
  The type `name` names, with its JSON Schema as `schema`. `raw` takes any
  object, so its `schema` is `null`. A name the catalogue doesn't hold
  answers 404 `not_found`.
  """
  @spec show(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def show(conn, %{"name" => name}) do
    with {:ok, {name, document}} <- Credentials.fetch_schema_document(name) do
      json(conn, %{data: %{name: name, title: title(name), schema: document}})
    end
  end

  defp title("raw"), do: "Raw JSON"
  defp title(name), do: PackageName.short_name(name)
end
