defmodule LightningWeb.AuditLive.Index do
  @moduledoc """
  LiveView for listing Audit events
  """
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :ensure_admin}

  alias Lightning.Auditing

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_menu_item: :audit),
     layout: {LightningWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(:page_title, "Audit")
    |> assign(:page, Auditing.list_all(params))
  end

  # The shape the design system's AuditEvent type expects. Only what the
  # page shows: the rest of the metadata stays on the server.
  defp events_json(audits) do
    Enum.map(audits, fn audit ->
      %{
        id: audit.id,
        insertedAt: audit.inserted_at,
        event: audit.event,
        itemType: audit.item_type,
        itemId: audit.item_id,
        actorId: audit.actor_id,
        actorLabel: audit.actor_display.label,
        actorIdentifier: audit.actor_display.identifier,
        changes: %{
          before: values(audit.changes.before),
          after: values(audit.changes.after)
        }
      }
      |> Map.merge(credential_bodies(audit))
    end)
  end

  # Scalars as they are; anything nested as JSON text, since the page prints text.
  defp values(nil), do: nil
  defp values(map), do: Map.new(map, fn {key, value} -> {key, value(value)} end)

  defp value(value)
       when is_binary(value) or is_number(value) or is_boolean(value) or
              is_nil(value),
       do: value

  defp value(value), do: Jason.encode!(value)

  # Encrypted per-environment credential bodies, keyed "body:<env>". The
  # type has the key optional, not nullable, so an audit without any omits it.
  defp credential_bodies(audit) do
    metadata = audit.metadata || %{}

    case Map.get(metadata, :credential_bodies) ||
           Map.get(metadata, "credential_bodies") do
      bodies when is_map(bodies) and map_size(bodies) > 0 ->
        %{credentialBodies: bodies}

      _ ->
        %{}
    end
  end
end
