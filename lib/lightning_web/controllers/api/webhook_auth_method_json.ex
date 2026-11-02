defmodule LightningWeb.API.WebhookAuthMethodJSON do
  @moduledoc """
  Renders a project's webhook auth methods.

  A method's secret goes out only when the controller asks: `:api_key` for the
  `201` that creates an `api` method, and `:secret` (the `api_key`, or the
  `password` of a `basic` method) for a stepped-up session token.

  The list shows a method's `username` and `api_key_last_characters` only to a
  caller who may manage it; anyone else gets them as null.
  """
  import LightningWeb.API.Helpers

  alias Lightning.Projects.Project
  alias Lightning.Workflows.WebhookAuthMethod
  alias LightningWeb.Router.Helpers, as: Routes

  @type secrets :: nil | :api_key | :secret

  @spec index(Plug.Conn.t(), Project.t(), Scrivener.Page.t(), boolean()) ::
          map()
  def index(conn, project, page, hints?) do
    %{
      data:
        Enum.map(
          page.entries,
          &(conn |> resource(project.id, &1, nil) |> hints(hints?))
        ),
      links: pagination_links(conn, page, %{})
    }
  end

  @spec show(Plug.Conn.t(), WebhookAuthMethod.t(), secrets()) :: map()
  def show(conn, auth_method, secrets) do
    %{data: resource(conn, auth_method.project_id, auth_method, secrets)}
  end

  defp resource(conn, project_id, auth_method, secrets) do
    %{
      type: "webhook_auth_methods",
      id: auth_method.id,
      attributes:
        Map.merge(
          %{
            name: auth_method.name,
            auth_type: auth_method.auth_type,
            username: username(auth_method),
            api_key_last_characters: last_characters(auth_method),
            triggers:
              Enum.map(
                auth_method.triggers,
                &%{id: &1.id, workflow_id: &1.workflow_id}
              ),
            inserted_at: auth_method.inserted_at,
            updated_at: auth_method.updated_at
          },
          secret(auth_method, secrets)
        ),
      relationships: %{},
      links: %{
        self:
          Routes.url(conn) <>
            "/api/projects/#{project_id}/webhook_auth_methods/#{auth_method.id}"
      }
    }
  end

  defp hints(resource, true), do: resource

  defp hints(resource, false) do
    update_in(
      resource.attributes,
      &%{&1 | username: nil, api_key_last_characters: nil}
    )
  end

  defp username(%WebhookAuthMethod{auth_type: :basic, username: username}),
    do: username

  defp username(%WebhookAuthMethod{}), do: nil

  defp last_characters(%WebhookAuthMethod{auth_type: :api, api_key: key})
       when is_binary(key),
       do: String.slice(key, -5, 5)

  defp last_characters(%WebhookAuthMethod{}), do: nil

  defp secret(%WebhookAuthMethod{auth_type: :api} = auth_method, secrets)
       when secrets in [:api_key, :secret],
       do: %{api_key: auth_method.api_key}

  defp secret(%WebhookAuthMethod{auth_type: :basic} = auth_method, :secret),
    do: %{password: auth_method.password}

  defp secret(%WebhookAuthMethod{}, _secrets), do: %{}
end
