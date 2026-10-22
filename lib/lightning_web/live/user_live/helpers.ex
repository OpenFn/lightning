defmodule LightningWeb.UserLive.Helpers do
  @moduledoc """
  What the users admin LiveViews share: the admin check every event makes
  again, the account lookup, and the props shape the design system expects.
  """
  import LightningWeb.Components.DesignSystem, only: [reply_error: 2]

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @doc "The mount gate is `:ensure_admin`; every event checks the same policy again."
  def authorize(socket) do
    if Permissions.can?(
         Users,
         :access_admin_space,
         socket.assigns.current_user,
         {}
       ),
       do: :ok,
       else:
         reply_error(socket, "You are not authorized to perform this action.")
  end

  @doc """
  The account for an id from the route or a payload. The id may be anything;
  only a UUID of an existing account passes.
  """
  def fetch_user(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %User{} = user <- Accounts.get_user(uuid) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  @doc "`fetch_user/1` as a `with` step in an event handler: a miss replies."
  def fetch_user(socket, id) do
    case fetch_user(id) do
      {:ok, user} -> {:ok, user}
      :error -> reply_error(socket, "User not found")
    end
  end

  @doc "The shape the design system's `AdminUserRow` type expects."
  def user_json(%User{} = user) do
    %{
      id: user.id,
      firstName: user.first_name,
      lastName: user.last_name,
      email: user.email,
      role: user.role,
      supportUser: user.support_user,
      disabled: user.disabled,
      scheduledDeletion: user.scheduled_deletion
    }
  end
end
