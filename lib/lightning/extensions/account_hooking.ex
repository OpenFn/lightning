defmodule Lightning.Extensions.AccountHooking do
  @moduledoc """
  Allows handling user creation or registration atomically without relying on async events.
  """
  alias Ecto.Changeset
  alias Lightning.Accounts.User

  @callback handle_register_user(attrs :: map()) ::
              {:ok, User.t()} | {:error, Changeset.t()}

  @callback handle_register_superuser(attrs :: map()) ::
              {:ok, User.t()} | {:error, Changeset.t()}

  @callback handle_create_user(attrs :: map()) ::
              {:ok, User.t()} | {:error, Changeset.t()}
end
