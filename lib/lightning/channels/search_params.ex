defmodule Lightning.Channels.SearchParams do
  @moduledoc """
  Parses and validates search/filter parameters for ChannelRequest queries.
  """

  use Lightning.Schema

  @primary_key false
  embedded_schema do
    field :channel_id, :binary_id
  end

  @type t :: %__MODULE__{
          channel_id: Ecto.UUID.t() | nil
        }

  @doc """
  Builds an Ecto changeset from raw URL params (string-keyed map).
  Use this for form binding; use `new/1` to get a validated struct.
  """
  def changeset(params \\ %{}) do
    %__MODULE__{}
    |> cast(params, [:channel_id])
    |> validate_uuid(:channel_id)
  end

  @doc """
  Builds a SearchParams struct from raw URL params (string-keyed map).
  Invalid or missing fields are silently dropped — in particular, a
  non-UUID `channel_id` will be coerced to nil rather than raising.
  """
  def new(params) do
    case apply_action(changeset(params), :validate) do
      {:ok, struct} -> struct
      {:error, _changeset} -> %__MODULE__{}
    end
  end

  defp validate_uuid(changeset, field) do
    validate_change(changeset, field, fn _, value ->
      case Ecto.UUID.cast(value) do
        {:ok, _} -> []
        :error -> [{field, "is not a valid UUID"}]
      end
    end)
  end
end
