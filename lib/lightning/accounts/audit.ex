defmodule Lightning.Accounts.Audit do
  @moduledoc """
  Model for storing changes to users.
  """
  use Lightning.Auditing.Audit,
    repo: Lightning.Repo,
    item: "user",
    events: ["created"]

  alias Lightning.Accounts.User

  @recorded ~w(email first_name last_name role confirmed_at)a

  @spec user_created(User.t(), Lightning.ServiceAccount.t()) ::
          Ecto.Changeset.t()
  def user_created(%User{} = user, actor) do
    event("created", user.id, actor, %{after: Map.take(user, @recorded)})
  end
end
