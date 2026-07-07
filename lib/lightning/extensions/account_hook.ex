defmodule Lightning.Extensions.AccountHook do
  @moduledoc false
  @behaviour Lightning.Extensions.AccountHooking

  alias Ecto.Changeset
  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Repo

  @spec handle_register_user(map()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def handle_register_user(
        %{sso_identity: %{provider: provider, uid: uid}} = attrs
      ) do
    attrs = Map.delete(attrs, :sso_identity)

    with {:ok, user} <-
           %User{}
           |> User.sso_registration_changeset(attrs)
           |> Repo.insert(),
         {:ok, _identity} <- link_identity(user, provider, uid) do
      {:ok, user}
    end
  end

  def handle_register_user(attrs) do
    with {:ok, data} <-
           User.user_registration_changeset(attrs)
           |> Changeset.apply_action(:insert) do
      Repo.insert(struct(User, data))
    end
  end

  @spec handle_register_superuser(map()) ::
          {:ok, User.t()} | {:error, Changeset.t()}
  def handle_register_superuser(attrs) do
    with {:ok, data} <-
           User.superuser_registration_changeset(attrs)
           |> Ecto.Changeset.apply_action(:insert) do
      struct(User, data) |> Repo.insert()
    end
  end

  @spec handle_create_user(map()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def handle_create_user(attrs) do
    %User{}
    |> User.changeset(attrs)
    |> Repo.insert()
  end

  defp link_identity(%User{} = user, provider, uid) do
    Accounts.link_user_identity(user, provider, uid)
  end
end
