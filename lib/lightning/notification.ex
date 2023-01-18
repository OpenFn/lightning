defmodule Lightning.Notifications do
  @moduledoc """
  Context for working with Notification records.
  """

  alias Lightning.Repo

  alias Lightning.Accounts.Notification

  @doc """
  Creates a notification.

  ## Examples

      iex> create_notification(%field: value})
      {:ok, %Notification{}}

      iex> create_notification(%field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_notification(attrs \\ %{}) do
    %Notification{}
    |> Notification.changeset(attrs)
    |> Repo.insert()
  end
end
