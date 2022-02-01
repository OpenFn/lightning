defmodule Lightning.Jobs.Job do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "jobs" do
    field :body, :string
    field :enabled, :boolean, default: false
    field :name, :string

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [:name, :body, :enabled])
    |> validate_required([:name, :body, :enabled])
  end
end
