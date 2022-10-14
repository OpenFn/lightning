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
  Updates a reason.

  ## Examples

      iex> update_reason(reason, %{field: new_value})
      {:ok, %InvocationReason{}}

      iex> update_reason(reason, %{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def update_reason(%InvocationReason{} = reason, attrs) do
    reason
    |> InvocationReason.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a reason.

  ## Examples

      iex> delete_reason(reason)
      {:ok, %InvocationReason{}}

      iex> delete_reason(reason)
      {:error, %Ecto.Changeset{}}

  """
  def delete_reason(%InvocationReason{} = reason) do
    Repo.delete(reason)
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
