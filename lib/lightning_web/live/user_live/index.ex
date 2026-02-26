defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @default_sort "email"
  @allowed_sorts ~w(first_name last_name email role enabled support_user scheduled_deletion)
  @default_page_size 10
  @max_page_size 100

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      socket =
        assign(socket,
          active_menu_item: :users
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
    socket =
      socket
      |> assign(:table_params, normalize_table_params(params))
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
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

  defp normalize_table_params(params) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)

    %{
      "filter" => normalize_filter(Map.get(params, "filter")),
      "sort" => normalize_sort(Map.get(params, "sort")),
      "dir" => normalize_dir(Map.get(params, "dir")),
      "page" => Map.get(params, "page") |> parse_positive_int(1) |> Integer.to_string(),
      "page_size" =>
        Map.get(params, "page_size")
        |> parse_positive_int(@default_page_size)
        |> min(@max_page_size)
        |> Integer.to_string()
    }
  end

  defp normalize_sort(sort) when is_binary(sort) do
    if sort in @allowed_sorts, do: sort, else: @default_sort
  end

  defp normalize_sort(sort) when is_atom(sort) do
    sort
    |> Atom.to_string()
    |> normalize_sort()
  end

  defp normalize_sort(_), do: @default_sort

  defp normalize_dir(dir) when dir in ["asc", :asc], do: "asc"
  defp normalize_dir(dir) when dir in ["desc", :desc], do: "desc"
  defp normalize_dir(_), do: "asc"

  defp normalize_filter(nil), do: ""

  defp normalize_filter(filter) do
    filter
    |> to_string()
    |> String.trim()
  end

  defp parse_positive_int(value, _default) when is_integer(value) and value > 0,
    do: value

  defp parse_positive_int(value, default) do
    case Integer.parse(to_string(value || "")) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end
end
