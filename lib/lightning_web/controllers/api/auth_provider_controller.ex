defmodule LightningWeb.API.AuthProviderController do
  @moduledoc """
  The instance's single sign-on provider: one OpenID Connect provider people
  may sign in through as well as with a password. Only a superuser may use
  these routes, on a personal access token or a session token; anyone else is
  403 `forbidden`, the service account included. The client secret is never
  returned.

  `GET /api/auth_provider` reads it, or answers 404 `not_found` when none is
  set up.

  `PUT /api/auth_provider` sets it up (201) or replaces it (200). It takes
  `name`, `discovery_url` and `client_id`, all required, and `client_secret`,
  required when setting up and kept when left out of a replace. Before saving
  it fetches the discovery document, so one that can't be fetched, isn't
  served over HTTPS or lacks an authorization or token endpoint is 422 with an
  entry at `#/discovery_url`. `redirect_uri`, which the provider sends people
  back to, is built from the instance's own URL and the name. The new settings
  apply to the next sign-in; a rename drops the old name's cached handler.

  `DELETE /api/auth_provider` turns single sign-on off at once and answers
  204, or 404 `not_found` when none is set up.

  A replace or delete that loses a race with another request deleting the
  provider is 409 `concurrent_edit`.
  """
  use LightningWeb, :controller

  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.AuthConfig
  alias Lightning.AuthProviders.AuthConfigForm
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.Plugs.AuthorizeAction

  action_fallback FallbackController

  @fields [:name, :discovery_url, :client_id, :client_secret]
  @saved [:name, :discovery_url, :client_id, :client_secret, :redirect_uri]

  plug AuthorizeAction,
       {:auth_providers, :read_auth_provider}
       when action == :show

  plug AuthorizeAction,
       {:auth_providers, :write_auth_provider}
       when action in [:update, :delete]

  def show(conn, _params) do
    with {:ok, provider} <- fetch_provider() do
      json(conn, %{data: provider_data(provider)})
    end
  end

  def update(conn, _params) do
    body = conn.body_params
    existing = AuthProviders.get_existing()

    with :ok <- Request.check_object(body),
         {:ok, attrs} <- validate(body, existing),
         {:ok, provider} <- save(existing, attrs) do
      conn
      |> put_status(if(existing, do: :ok, else: :created))
      |> json(%{data: provider_data(provider)})
    end
  end

  def delete(conn, _params) do
    with {:ok, provider} <- fetch_provider(),
         {:ok, _provider} <- AuthProviders.delete(provider) do
      send_resp(conn, 204, "")
    end
  end

  defp fetch_provider do
    case AuthProviders.get_existing() do
      %AuthConfig{} = provider -> {:ok, provider}
      nil -> {:error, :not_found}
    end
  end

  # A replace takes every field again, except the secret, which is kept when
  # left out. The discovery document is fetched only for a body that is
  # otherwise valid.
  defp validate(body, existing) do
    form = %AuthConfigForm{
      client_secret: existing && existing.client_secret,
      redirect_host: LightningWeb.Endpoint.url(),
      redirect_path_func: &"/authenticate/#{&1}/callback"
    }

    changeset =
      AuthConfigForm.change(
        form,
        Map.take(body, Enum.map(@fields, &to_string/1))
      )

    unknown = Request.unknown_keys(body, [], @fields)

    if unknown == [] and changeset.valid?,
      do: check_discovery(changeset),
      else: Errors.refuse(unknown ++ Errors.from_changeset(changeset))
  end

  defp check_discovery(changeset) do
    checked = AuthConfigForm.validate_provider(changeset)

    if checked.valid?,
      do: {:ok, checked |> Ecto.Changeset.apply_changes() |> Map.take(@saved)},
      else: Errors.refuse(Errors.from_changeset(checked))
  end

  defp save(nil, attrs), do: AuthProviders.create(attrs)

  defp save(%AuthConfig{name: old_name} = existing, attrs) do
    with {:ok, provider} <- AuthProviders.update(existing, attrs) do
      if provider.name != old_name, do: AuthProviders.remove_handler(old_name)
      {:ok, provider}
    end
  end

  defp provider_data(%AuthConfig{} = provider) do
    %{
      name: provider.name,
      discovery_url: provider.discovery_url,
      client_id: provider.client_id,
      redirect_uri: provider.redirect_uri,
      inserted_at: provider.inserted_at,
      updated_at: provider.updated_at
    }
  end
end
