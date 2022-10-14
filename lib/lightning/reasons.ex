defmodule Lightning.InvocationReasons do
  @moduledoc """
  The InvocationReasons context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.InvocationReason

  @doc """
  Creates a reason.

  ## Examples

      iex> create_reason(%{field: value})
      {:ok, %InvocationReason{}}

      iex> create_reason(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def create_reason(attrs \\ %{}) do
    %InvocationReason{}
    |> InvocationReason.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking reason changes.

  ## Examples

      iex> change_reason(reason)
      %Ecto.Changeset{data: %InvocationReason{}}

  """
  def change_reason(%InvocationReason{} = reason, attrs \\ %{}) do
    InvocationReason.changeset(reason, attrs)
  end
end
