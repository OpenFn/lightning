defmodule Lightning.InvocationReasons do
  @moduledoc """
  The InvocationReasons context.
  """

  import Ecto.Query, warn: false
  alias Lightning.Repo
  alias Lightning.InvocationReason
  alias Lightning.Invocation.Dataclip
  alias Lightning.Jobs.Trigger

  def build(%Trigger{type: type, id: trigger_id}, %Dataclip{id: dataclip_id}) do
    case type do
      type when type in [:webhook, :cron] ->
        %InvocationReason{}
        |> InvocationReason.changeset(%{
          type: type,
          trigger_id: trigger_id,
          dataclip_id: dataclip_id
        })

      _ ->
        %InvocationReason{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(
          :type,
          "Type must be either :webhook or :cron"
        )
    end
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
