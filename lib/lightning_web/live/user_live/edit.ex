defmodule LightningWeb.UserLive.Edit do
  @moduledoc """
  The admin user form: a new account on `/settings/users/new`, any account
  on `/settings/users/:id`.
  """
  use LightningWeb, :live_view

  import LightningWeb.UserLive.Helpers

  on_mount {LightningWeb.Hooks, :ensure_admin}

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_menu_item: :users, user: nil),
     layout: {LightningWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    case fetch_user(id) do
      {:ok, user} ->
        assign(socket, page_title: "Edit User", user: user)

      :error ->
        socket
        |> put_flash(:error, "User not found")
        |> push_navigate(to: ~p"/settings/users")
    end
  end

  defp apply_action(socket, :new, _params),
    do: assign(socket, page_title: "New User", user: nil)

  # The page sends its fields once, on Save, and checks the required ones
  # itself; the changeset checks everything, as it did for the old form.
  # Which account is saved is the route's to know, not the payload's.
  @impl true
  def handle_event("save_user", params, socket) do
    with :ok <- authorize(socket) do
      save(
        socket,
        socket.assigns.live_action,
        socket.assigns.user,
        user_attrs(params)
      )
    end
  end

  # The new-user form never showed the edit-only fields.
  defp save(socket, :new, nil, attrs) do
    attrs = Map.drop(attrs, ["disabled", "scheduled_deletion"])

    case Accounts.create_user(attrs, socket.assigns.current_user) do
      {:ok, user} ->
        {level, message} =
          case Accounts.deliver_user_confirmation_instructions(
                 socket.assigns.current_user,
                 user
               ) do
            {:ok, _email} ->
              {:info, "User created successfully"}

            {:error, reason} ->
              Logger.error(
                "Failed to send confirmation email #{inspect(reason)}"
              )

              {:error,
               "User created, but the confirmation email could not be sent"}
          end

        {:reply, %{},
         socket
         |> put_flash(level, message)
         |> push_navigate(to: ~p"/settings/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, changeset)
    end
  end

  defp save(socket, :edit, %User{} = user, attrs) do
    case Accounts.update_user(user, attrs, socket.assigns.current_user) do
      {:ok, _user} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "User updated successfully")
         |> push_navigate(to: ~p"/settings/users")}

      {:error, %Ecto.Changeset{} = changeset} ->
        reply_error(socket, changeset)
    end
  end

  defp save(socket, _action, _user, _attrs),
    do: reply_error(socket, "User not found")

  @strings %{
    "firstName" => "first_name",
    "lastName" => "last_name",
    "email" => "email",
    "password" => "password",
    "role" => "role",
    "scheduledDeletion" => "scheduled_deletion"
  }
  @flags %{"supportUser" => "support_user", "disabled" => "disabled"}

  # The page's camelCase values as the changeset's params: named keys only,
  # strings and booleans only, so a crafted payload can't reach a field the
  # form never had (`confirmed`) or make the cast raise.
  defp user_attrs(params) when is_map(params) do
    strings =
      for {key, field} <- @strings, is_binary(params[key]), into: %{} do
        {field, params[key]}
      end

    for {key, field} <- @flags, is_boolean(params[key]), into: strings do
      {field, params[key]}
    end
  end

  defp user_attrs(_params), do: %{}
end
