defmodule Lightning.AuthProviders.Scope do
  @moduledoc """
  """

  use Ecto.Schema
  import Ecto.Changeset

  @type t :: %__MODULE__{
          label: String.t(),
          value: String.t(),
          editable: boolean()
        }

  @primary_key false
  embedded_schema do
    field :label, :string
    field :value, :string
    field :editable, :boolean, default: true
  end

  def new(params) do
    %__MODULE__{}
    |> cast(params, [:label, :value, :editable])
    |> apply_action!(:validate)
  end
end
