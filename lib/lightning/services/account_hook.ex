defmodule Lightning.Services.AccountHook do
  @moduledoc """
  Allows handling user creation or registration atomically without relying on async events.
  """
  @behaviour Lightning.Extensions.AccountHooking

  import Lightning.Services.AdapterHelper

  alias Ecto.Changeset
  alias Lightning.Accounts.User

  @spec handle_register_user(map()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def handle_register_user(attrs) do
    adapter().handle_register_user(attrs)
  end

  @spec handle_register_superuser(map()) ::
          {:ok, User.t()} | {:error, Changeset.t()}
  def handle_register_superuser(attrs) do
    adapter().handle_register_superuser(attrs)
  end

  @spec handle_create_user(map()) :: {:ok, User.t()} | {:error, Changeset.t()}
  def handle_create_user(attrs) do
    adapter().handle_create_user(attrs)
  end

  defp adapter, do: adapter(:account_hook)
end
