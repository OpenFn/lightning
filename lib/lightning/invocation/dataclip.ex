defmodule Lightning.Invocation.Dataclip do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "dataclips" do
    field :body, :map
    field :type, Ecto.Enum, values: [:http_request, :global]

    timestamps()
  end

  @doc false
  def changeset(dataclip, attrs) do
    dataclip
    |> cast(attrs, [:body, :type])
    |> validate_required([:body, :type])
  end
end
