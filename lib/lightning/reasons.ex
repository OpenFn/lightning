defmodule Lightning.InvocationReasons do
  @moduledoc """
  The InvocationReasons context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.InvocationReason
  alias Lightning.Invocation.Dataclip
  alias Lightning.Jobs.Trigger

  def build(:manual = type, %{
        user: %{id: user_id},
        dataclip: %Dataclip{id: dataclip_id}
      }) do
    InvocationReason.new(%{
      type: type,
      dataclip_id: dataclip_id,
      user_id: user_id
    })
  end

  def build(%Trigger{type: type, id: trigger_id}, %Dataclip{id: dataclip_id}) do
    InvocationReason.new(%{
      type: type,
      trigger_id: trigger_id,
      dataclip_id: dataclip_id
    })
  end

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
end
