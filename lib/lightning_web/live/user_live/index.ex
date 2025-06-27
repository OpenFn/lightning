defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  import LightningWeb.UserLive.Components

  alias Lightning.Accounts
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      socket =
        assign(socket,
          users: list_users("", "email", "asc"),
          active_menu_item: :users,
          sort_key: "email",
          sort_direction: "asc",
          filter: ""
        )

      {:ok, socket, layout: {LightningWeb.Layouts, :settings}}
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

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:delete_user, nil)
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    socket
    |> assign(:page_title, "Users")
    |> assign(:delete_user, Accounts.get_user!(id))
  end

  @impl true
  def handle_event(
        "cancel_deletion",
        %{"id" => user_id},
        socket
      ) do
    case Accounts.cancel_scheduled_deletion(user_id) do
      {:ok, _change} ->
        {:noreply,
         socket
         |> put_flash(:info, "User deletion canceled")
         |> push_navigate(to: ~p"/settings/users")}

      {:error, _reason} ->
        {:noreply,
         socket
         |> put_flash(:error, "Cancel user deletion failed")}
    end
  end

  def handle_event("sort", %{"by" => sort_key}, socket) do
    {sort_key, sort_direction} =
      case socket.assigns do
        %{sort_key: ^sort_key, sort_direction: "asc"} ->
          {sort_key, "desc"}

        %{sort_key: ^sort_key, sort_direction: "desc"} ->
          {sort_key, "asc"}

        _ ->
          {sort_key, "asc"}
      end

    users = list_users(socket.assigns.filter, sort_key, sort_direction)

    {:noreply,
     assign(socket,
       users: users,
       sort_key: sort_key,
       sort_direction: sort_direction
     )}
  end

  def handle_event("filter", %{"value" => filter}, socket) do
    users = list_users(filter, socket.assigns.sort_key, socket.assigns.sort_direction)

    {:noreply,
     assign(socket,
       users: users,
       filter: filter
     )}
  end

  def handle_event("clear_filter", _params, socket) do
    users = list_users("", socket.assigns.sort_key, socket.assigns.sort_direction)

    {:noreply,
     assign(socket,
       users: users,
       filter: ""
     )}
  end

  # defp list_users do
  #   Accounts.list_users()
  # end

  defp list_users(filter, sort_key, sort_direction) do
    users = Accounts.list_users()

    users
    |> filter_users(filter)
    |> sort_users(sort_key, sort_direction)
  end

  defp filter_users(users, "") do
    users
  end

  defp filter_users(users, filter) do
    filter_lower = String.downcase(filter)

    Enum.filter(users, fn user ->
      String.contains?(String.downcase(user.first_name || ""), filter_lower) ||
      String.contains?(String.downcase(user.last_name || ""), filter_lower) ||
      String.contains?(String.downcase(user.email || ""), filter_lower) ||
      String.contains?(String.downcase(to_string(user.role)), filter_lower)
    end)
  end

  defp sort_users(users, sort_key, sort_direction) do
    compare_fn = case sort_direction do
      "asc" -> &<=/2
      "desc" -> &>=/2
    end

    Enum.sort_by(users, fn user ->
      case sort_key do
        "first_name" -> user.first_name || ""
        "last_name" -> user.last_name || ""
        "email" -> user.email || ""
        "role" -> to_string(user.role)
        "enabled" -> !user.disabled
        "support_user" -> user.support_user
        "scheduled_deletion" -> user.scheduled_deletion || ~U[9999-12-31 23:59:59Z]
        _ -> user.email || ""
      end
    end, compare_fn)
  end
end
