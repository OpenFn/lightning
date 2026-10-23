defmodule LightningWeb.UserLive.Index do
  @moduledoc """
  The users admin page: every account on the instance, and the deletion
  dialog that `/settings/users/:id/delete` opens over the list.
  """
  use LightningWeb, :live_view

  import LightningWeb.UserLive.Helpers

  on_mount {LightningWeb.Hooks, :ensure_admin}

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :users,
       page_title: "Users",
       delete_user: nil
     )
     |> load(), layout: {LightningWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params),
    do: assign(socket, delete_user: nil)

  # The dialog's account is the route's; the page never says who to delete.
  defp apply_action(socket, :delete, %{"id" => id}) do
    case fetch_user(id) do
      {:ok, user} ->
        assign(socket, delete_user: user)

      :error ->
        socket
        |> put_flash(:error, "User not found")
        |> push_navigate(to: ~p"/settings/users")
    end
  end

  # The page sorts and filters in the browser; the list arrives as stored.
  defp load(socket), do: assign(socket, users: Accounts.list_users())

  @impl true
  def handle_event("cancel_deletion", params, socket) when is_map(params) do
    with :ok <- authorize(socket),
         {:ok, user} <- fetch_user(socket, params["id"]) do
      case Accounts.cancel_scheduled_deletion(user.id) do
        {:ok, _user} ->
          {:reply, %{},
           socket |> put_flash(:info, "User deletion canceled") |> load()}

        {:error, _changeset} ->
          reply_error(socket, "Cancel user deletion failed")
      end
    end
  end

  # The dialog's one action: schedule the account for deletion, or delete
  # at once one that is already scheduled. The typed email confirms either.
  # The account is the one the route opened, read again now: it may be
  # gone, or its role may have changed. The dialog said which of the two
  # actions it was; if another admin scheduled the account meanwhile, the
  # confirm must not become a purge.
  def handle_event("delete_user", params, socket) when is_map(params) do
    with :ok <- authorize(socket),
         {:ok, opened} <- open_for_deletion(socket),
         {:ok, user} <- fetch_user(socket, opened.id),
         :ok <- same_action?(socket, opened, user) do
      email = if is_binary(params["email"]), do: params["email"], else: ""

      if user.scheduled_deletion,
        do: purge(socket, user, email),
        else: schedule(socket, user, email)
    end
  end

  def handle_event(event, _params, socket)
      when event in ["cancel_deletion", "delete_user"],
      do: reply_error(socket, "Invalid request")

  defp open_for_deletion(%{
         assigns: %{live_action: :delete, delete_user: %User{} = user}
       }),
       do: {:ok, user}

  defp open_for_deletion(socket), do: reply_error(socket, "User not found")

  defp same_action?(socket, opened, user) do
    if is_nil(opened.scheduled_deletion) == is_nil(user.scheduled_deletion),
      do: :ok,
      else:
        reply_error(
          socket,
          "This account's deletion changed since the dialog opened. Reload the page."
        )
  end

  defp schedule(socket, user, email) do
    case Accounts.schedule_user_deletion(user, email) do
      {:ok, %User{}} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "User scheduled for deletion")
         |> push_navigate(to: ~p"/settings/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, deletion_error(changeset))
    end
  end

  # The changeset puts every refusal on the email field; the dialog shows
  # the first as its one line.
  defp deletion_error(changeset) do
    changeset
    |> LightningWeb.CoreComponents.translate_errors()
    |> Map.values()
    |> List.flatten()
    |> List.first("Please fix the errors below.")
  end

  # The dialog can be opened on any id, so the checks the schedule
  # changeset makes are made again when the account is purged; the activity
  # check is fresh, as a run may have been created since the dialog opened.
  defp purge(socket, user, email) do
    case Accounts.purge_confirmed_user(user, email) do
      {:error, :superuser} ->
        reply_error(socket, "You can't delete a superuser account.")

      {:error, :email_mismatch} ->
        reply_error(socket, "This email doesn't match your current email")

      {:error, :has_activity} ->
        {:reply, %{},
         socket
         |> put_flash(
           :error,
           "Cannot delete user that has activities in other projects"
         )
         |> push_navigate(to: ~p"/settings/users")}

      result ->
        purged(socket, result)
    end
  end

  defp purged(socket, :ok) do
    {:reply, %{},
     socket
     |> put_flash(:info, "User deleted")
     |> push_navigate(to: ~p"/settings/users")}
  end

  defp purged(socket, {:error, _changeset}) do
    {:reply, %{},
     socket
     |> put_flash(:error, "Cannot delete user with associated activity")
     |> push_navigate(to: ~p"/settings/users")}
  end

  # The shape the design system's AdminDeleteUser type expects.
  defp delete_user_json(nil), do: nil

  defp delete_user_json(%User{} = user) do
    %{
      id: user.id,
      email: user.email,
      scheduledDeletion: user.scheduled_deletion,
      hasActivityInProjects: Accounts.has_activity_in_projects?(user)
    }
  end
end
