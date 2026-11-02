defmodule LightningWeb.API.AuditEventJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  @fields ~w(event item_type item_id actor_type actor_id inserted_at)a

  # Secrets some audit modules record in `changes`, encoded but not
  # encrypted (OAuth client secrets are only Base64), so they never leave.
  @secret_changes %{
    "oauth_client" => ~w(client_secret),
    "webhook_auth_method" => ~w(username password api_key)
  }

  def render("index.json", %{page: page, filters: filters, conn: conn}) do
    %{
      data: Enum.map(page.entries, &resource/1),
      included: [],
      links: pagination_links(conn, page, filters)
    }
  end

  defp resource(audit) do
    %{
      type: "audit_events",
      id: audit.id,
      attributes:
        audit
        |> Map.take(@fields)
        |> Map.merge(%{
          actor_display: actor_display(audit.actor_display),
          changes: changes(audit.changes, audit.item_type),
          metadata: Map.delete(audit.metadata || %{}, "credential_bodies")
        }),
      relationships: %{},
      links: %{}
    }
  end

  defp actor_display(%{label: label, identifier: nil}), do: label

  defp actor_display(%{label: label, identifier: identifier}),
    do: "#{label} (#{identifier})"

  defp changes(nil, _item_type), do: %{before: nil, after: nil}

  defp changes(changes, item_type) do
    secrets = Map.get(@secret_changes, item_type, [])

    %{
      before: drop_secrets(changes.before, secrets),
      after: drop_secrets(changes.after, secrets)
    }
  end

  defp drop_secrets(nil, _secrets), do: nil
  defp drop_secrets(fields, secrets), do: Map.drop(fields, secrets)
end
