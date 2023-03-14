defmodule LightningWeb.AuditLive.Index do
  @moduledoc """
  LiveView for listing Audit events
  """
  use LightningWeb, :live_view
  alias Lightning.Auditing
  alias Lightning.Policies.{Users, Permissions}

  @impl true
  def mount(_params, _session, socket) do
    can_view_credentials_audit_trail =
      Users
      |> Permissions.can(
        :view_credentials_audit_trail,
        socket.assigns.current_user
      )

    if can_view_credentials_audit_trail do
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
       ), layout: {LightningWeb.LayoutView, :settings}}
    else
      put_flash(socket, :error, "You can't access that page")
      |> push_redirect(to: "/")
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

  def diff(assigns) do
    lhs = assigns.metadata.before
    rhs = assigns.metadata.after

    assigns =
      assign(assigns,
        changes:
          Enum.zip([lhs |> Map.keys(), lhs |> Map.values(), rhs |> Map.values()])
      )

    ~H"""
    <%= for {field, old, new} <- @changes do %>
      <li><%= field %>&nbsp; <%= old %>
        <Heroicons.arrow_right class="h-5 w-5 inline-block mr-2" />
        <%= new %></li>
    <% end %>
    """
  end
end
