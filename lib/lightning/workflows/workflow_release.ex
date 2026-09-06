defmodule Lightning.Workflows.WorkflowRelease do
  @moduledoc """
  A published version of a workflow, recorded at each go-live and promote.

  Unlike `Lightning.Workflows.Snapshot` (captured on every save) a release marks
  a deliberate publish event. `version_number` is sequential per workflow and is
  what the UI shows as v1, v2, … Each release always resolves to a real
  `Snapshot` for its content, and carries provenance: who published it and, for a
  promote, which sandbox it came from.
  """
  use Lightning.Schema

  alias Lightning.Accounts.User
  alias Lightning.Projects.Project
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow

  @type kind :: :go_live | :promote

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          version_number: pos_integer() | nil,
          kind: kind() | nil,
          workflow_id: Ecto.UUID.t() | nil,
          snapshot_id: Ecto.UUID.t() | nil,
          published_by_id: Ecto.UUID.t() | nil,
          source_project_id: Ecto.UUID.t() | nil,
          inserted_at: DateTime.t() | nil
        }

  @kinds [:go_live, :promote]

  schema "workflow_releases" do
    field :version_number, :integer
    field :kind, Ecto.Enum, values: @kinds

    belongs_to :workflow, Workflow
    belongs_to :snapshot, Snapshot
    belongs_to :published_by, User
    belongs_to :source_project, Project

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  @doc false
  def changeset(release, attrs) do
    release
    |> cast(attrs, [
      :version_number,
      :kind,
      :workflow_id,
      :snapshot_id,
      :published_by_id,
      :source_project_id
    ])
    |> validate_required([:version_number, :kind, :workflow_id, :snapshot_id])
    |> validate_number(:version_number, greater_than: 0)
    |> unique_constraint([:workflow_id, :version_number],
      error_key: :version_number,
      message: "exists for this workflow"
    )
    |> foreign_key_constraint(:workflow_id)
    |> foreign_key_constraint(:snapshot_id)
  end
end
