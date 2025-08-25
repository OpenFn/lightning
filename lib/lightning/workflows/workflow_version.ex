defmodule Lightning.Workflows.WorkflowVersion do
  @moduledoc "Provenance rows for workflow versions (hash + source + inserted_at)."
  use Lightning.Schema
  import Ecto.Changeset
  alias Lightning.Workflows.Workflow

  @sources ~w(app cli)
  @hash_regex ~r/^[a-f0-9]{12}$/

  schema "workflow_versions" do
    field :hash, :string
    field :source, :string
    belongs_to :workflow, Workflow

    timestamps(
      type: :utc_datetime_usec,
      updated_at: false,
      inserted_at: :inserted_at
    )
  end

  def changeset(version, attrs) do
    version
    |> cast(attrs, [:hash, :source, :workflow_id])
    |> validate_required([:hash, :source, :workflow_id])
    |> validate_format(:hash, @hash_regex)
    |> validate_inclusion(:source, @sources)
    |> foreign_key_constraint(:workflow_id)
    |> unique_constraint(:hash,
      name: :workflow_versions_workflow_id_hash_index,
      message: "has already been taken"
    )
    |> check_constraint(:hash,
      name: :hash_is_12_hex,
      message: "must be 12 lowercase hex chars"
    )
    |> check_constraint(:source,
      name: :source_is_known,
      message: "must be 'app' or 'cli'"
    )
  end
end
