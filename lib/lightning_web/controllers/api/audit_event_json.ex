defmodule LightningWeb.API.AuditEventJSON do
  @moduledoc false

  import LightningWeb.API.Helpers

  @fields ~w(event item_type item_id actor_type actor_id inserted_at)a

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
          changes: changes(audit.changes),
          metadata: Map.delete(audit.metadata || %{}, "credential_bodies")
        }),
      relationships: %{},
      links: %{}
    }
  end

  defp actor_display(%{label: label, identifier: nil}), do: label

  defp actor_display(%{label: label, identifier: identifier}),
    do: "#{label} (#{identifier})"

  defp changes(nil), do: %{before: nil, after: nil}
  defp changes(changes), do: %{before: changes.before, after: changes.after}
end
