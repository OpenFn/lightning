defmodule Lightning.Workflows.WorkflowVersion do
  @moduledoc """
  Immutable provenance rows for workflow heads.

  - One row per head: `hash` (12-char lowercase hex), `source` ("app" | "cli"),
    `workflow_id`, `inserted_at` (UTC μs).
  - Append-only: `updated_at` disabled; rows are never mutated.
  - Uniqueness: `(workflow_id, hash)` unique; same hash may exist across workflows.
  - Validation mirrors DB checks: hash format, allowed sources, valid `workflow_id`.
  - Deterministic ordering via `:utc_datetime_usec` timestamps.
  - Use `Lightning.WorkflowVersions` to record/query and keep
    `workflows.version_history` in sync.
  """
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
  end
end
