defmodule LightningWeb.AuditLive.Index do
  @moduledoc """
  LiveView for listing Audit events
  """
  use LightningWeb, :live_view

  import PetalComponents.Badge

  alias Lightning.Auditing
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      {:ok,
       socket
       |> assign(
         active_menu_item: :audit,
         pagination_path:
           &Routes.audit_index_path(
             socket,
             :index,
             &1
           )
       ), layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       put_flash(socket, :nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
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

  def diff(%{audit: %{changes: %{before: nil, after: nil}}} = assigns) do
    env_bodies = get_env_bodies(assigns.audit)

    if Enum.empty?(env_bodies) do
      no_changes(assigns)
    else
      assigns = assign(assigns, env_bodies: env_bodies, changes: [])
      render_diff(assigns)
    end
  end

  def diff(%{audit: %{changes: %{before: lhs, after: rhs}}} = assigns)
      when map_size(lhs) == 0 and map_size(rhs) == 0 do
    env_bodies = get_env_bodies(assigns.audit)

    if Enum.empty?(env_bodies) do
      no_changes(assigns)
    else
      assigns = assign(assigns, env_bodies: env_bodies, changes: [])
      render_diff(assigns)
    end
  end

  def diff(assigns) do
    lhs = assigns.audit.changes.before || %{}
    rhs = assigns.audit.changes.after || %{}

    changes =
      lhs
      |> Map.keys()
      |> Enum.concat(Map.keys(rhs))
      |> Enum.sort()
      |> Enum.uniq()
      |> Enum.map(fn key ->
        {key, Map.get(lhs, key), Map.get(rhs, key)}
      end)

    env_bodies = get_env_bodies(assigns.audit)

    assigns = assign(assigns, changes: changes, env_bodies: env_bodies)
    render_diff(assigns)
  end

  defp get_env_bodies(audit) do
    metadata = audit.metadata || %{}

    bodies =
      Map.get(metadata, :credential_bodies) ||
        Map.get(metadata, "credential_bodies")

    case bodies do
      bodies when is_map(bodies) and map_size(bodies) > 0 ->
        bodies
        |> Enum.map(fn {key, encrypted_value} ->
          env_name = String.replace_prefix(key, "body:", "")
          {env_name, encrypted_value}
        end)
        |> Enum.sort_by(fn {name, _} -> name end)

      _ ->
        []
    end
  end

  defp render_diff(assigns) do
    ~H"""
    <.td colspan={4} class="!p-4 font-mono text-xs break-all">
      <%= if !Enum.empty?(@changes) do %>
        <ul class="p-2 bg-gray-50 rounded-md ring ring-gray-100 mb-3">
          <%= for {field, old, new} <- @changes do %>
            <li class="mb-2 last:mb-0">
              <span class="font-semibold">{field}</span>&nbsp;
              <%= if old != nil do %>
                <span class="text-gray-500 line-through">{format_value(old)}</span>
                <.icon
                  name="hero-arrow-right"
                  class="h-4 w-4 inline-block mx-2 text-gray-400"
                />
              <% end %>
              <span class="text-gray-900">{format_value(new)}</span>
            </li>
          <% end %>
        </ul>
      <% end %>

      <%= if !Enum.empty?(@env_bodies) do %>
        <ul class="p-2 bg-gray-50 rounded-md ring ring-gray-100">
          <%= for {env_name, encrypted_body} <- @env_bodies do %>
            <li class="mb-2 last:mb-0">
              <span class="font-semibold">body:{env_name}</span>&nbsp;
              <span class="text-gray-700 break-all">{encrypted_body}</span>
            </li>
          <% end %>
        </ul>
      <% end %>
    </.td>
    """
  end

  defp format_value(nil), do: ""
  defp format_value(value), do: value

  defp no_changes(assigns) do
    ~H"""
    <.td colspan={4} class="!p-6 font-mono text-xs break-all">
      No changes
    </.td>
    """
  end
end
