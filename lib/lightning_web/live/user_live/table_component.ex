defmodule LightningWeb.UserLive.TableComponent do
  @moduledoc false

  use LightningWeb, :live_component
  import LightningWeb.UserLive.Components

  alias Lightning.Accounts
  alias LightningWeb.Live.Helpers.TableHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.users_table
        socket={@socket}
        target={@myself}
        live_action={@live_action}
        delete_user={assigns[:delete_user]}
        users={@users}
        sort_key={@sort_key}
        sort_direction={@sort_direction}
        filter={@filter}
      />
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       users: list_users("", "email", "asc"),
       sort_key: "email",
       sort_direction: "asc",
       filter: ""
     )}
  end

  @impl true
  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  @impl true
  def handle_event("sort", %{"by" => sort_key}, socket) do
    {sort_key, sort_direction} =
      TableHelpers.toggle_sort_direction(
        socket.assigns.sort_direction,
        socket.assigns.sort_key,
        sort_key
      )

    users = list_users(socket.assigns.filter, sort_key, sort_direction)

    {:noreply,
     assign(socket,
       users: users,
       sort_key: sort_key,
       sort_direction: sort_direction
     )}
  end

  def handle_event("filter", %{"value" => filter}, socket) do
    users =
      list_users(filter, socket.assigns.sort_key, socket.assigns.sort_direction)

    {:noreply,
     assign(socket,
       users: users,
       filter: filter
     )}
  end

  def handle_event("clear_filter", _params, socket) do
    users =
      list_users("", socket.assigns.sort_key, socket.assigns.sort_direction)

    {:noreply,
     assign(socket,
       users: users,
       filter: ""
     )}
  end

  defp list_users(filter, sort_key, sort_direction) do
    users = Accounts.list_users()

    TableHelpers.filter_and_sort(
      users,
      filter,
      user_search_fields(),
      sort_key,
      sort_direction,
      user_sort_map()
    )
  end

  # Configuration for user table sorting
  defp user_sort_map do
    %{
      "first_name" => :first_name,
      "last_name" => :last_name,
      "email" => :email,
      "role" => fn user -> to_string(user.role) end,
      "enabled" => fn user -> !user.disabled end,
      "support_user" => :support_user,
      "scheduled_deletion" => fn user ->
        user.scheduled_deletion || ~U[9999-12-31 23:59:59Z]
      end
    }
  end

  defp user_search_fields do
    [:first_name, :last_name, :email, fn user -> to_string(user.role) end]
  end
end
