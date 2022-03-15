defmodule Lightning.Jobs.Trigger do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Jobs.Job

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "triggers" do
    field :comment, :string
    field :custom_path, :string
    belongs_to :job, Job

    field :type, :string, virtual: true, default: "webhook"

    timestamps()
  end

  @doc false
  def changeset(trigger, attrs) do
    trigger
    |> cast(attrs, [:comment, :custom_path, :type])
    |> validate_inclusion(:type, ["webhook"])
    |> validate_required([:type])
    |> assoc_constraint(:job)
  end
end
