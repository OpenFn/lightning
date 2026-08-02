defmodule Lightning.Extensions.AccountHook do
  @moduledoc false
  @behaviour Lightning.Extensions.AccountHooking

  alias Ecto.Changeset
  alias Lightning.Accounts.User
  alias Lightning.Repo

  @spec handle_register_user(map()) :: {:ok, User.t()} | {:error, Changeset.t()}
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
end
