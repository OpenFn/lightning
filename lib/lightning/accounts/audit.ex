defmodule Lightning.Accounts.Audit do
  @moduledoc """
  Model for storing changes to users.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "user",
    events: ["created", "updated"]

  alias Lightning.Accounts.User

  @recorded ~w(email first_name last_name role confirmed_at)a

  @spec user_created(User.t(), Lightning.ServiceAccount.t()) ::
          Ecto.Changeset.t()
  def user_created(%User{} = user, actor) do
    event("created", user.id, actor, %{after: Map.take(user, @recorded)})
  end

  @doc """
  The event for a change to a user, or `:no_changes` when the changeset
  changes nothing. A new password shows only as `password_changed` in the
  metadata, never as its hash.
  """
  @spec user_updated(Ecto.Changeset.t(), Lightning.ServiceAccount.t()) ::
          Ecto.Changeset.t() | :no_changes
  def user_updated(%Ecto.Changeset{data: %User{} = user} = changeset, actor) do
    changed = Enum.filter(@recorded, &Map.has_key?(changeset.changes, &1))
    password_changed = Map.has_key?(changeset.changes, :hashed_password)

    if changed == [] and not password_changed do
      :no_changes
    else
      event(
        "updated",
        user.id,
        actor,
        %{
          before: Map.take(user, changed),
          after: Map.take(changeset.changes, changed)
        },
        if(password_changed, do: %{password_changed: true}, else: %{})
      )
    end
  end
end
