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

  def diff(%{metadata: %{before: nil, after: nil}} = assigns) do
    no_changes(assigns)
  end

  def diff(%{metadata: %{before: lhs, after: rhs}} = assigns)
      when map_size(lhs) == 0 and map_size(rhs) == 0 do
    no_changes(assigns)
  end

  def diff(assigns) do
    lhs = assigns.metadata.before || %{}
    rhs = assigns.metadata.after || %{}

    changes =
      lhs
      |> Map.keys()
      |> Enum.concat(Map.keys(rhs))
      |> Enum.sort()
      |> Enum.uniq()
      |> Enum.map(fn key ->
        {key, Map.get(lhs, key), Map.get(rhs, key)}
      end)

    assigns = assign(assigns, changes: changes)

    ~H"""
    <.td colspan={4} class="!p-4 font-mono text-xs break-all">
      <ul class="p-2 bg-gray-50 rounded-md ring ring-gray-100">
        <%= for {field, old, new} <- @changes do %>
          <li class="mb-2 last:mb-0">
            <span class="font-semibold">{field}</span>&nbsp; {old}
            <.icon name="hero-arrow-right" class="h-4 w-4 inline-block mx-2" />
            {new}
          </li>
        <% end %>
      </ul>
    </.td>
    """
  end

  defp no_changes(assigns) do
    ~H"""
    <.td colspan={4} class="!p-6 font-mono text-xs break-all">
      No changes
    </.td>
    """
  end
end
