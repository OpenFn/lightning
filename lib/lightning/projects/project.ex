defmodule Lightning.Projects.Project do
  @moduledoc """
  Project model
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          project_users: [ProjectUser.t()] | Ecto.Association.NotLoaded.t()
        }

  @type retention_policy_type :: :retain_all | :retain_with_errors | :erase_all

  @retention_periods [7, 14, 30, 90, 180, 365]

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "projects" do
    field :name, :string
    field :description, :string
    field :scheduled_deletion, :utc_datetime
    field :requires_mfa, :boolean, default: false

    field :retention_policy, Ecto.Enum,
      values: [:retain_all, :retain_with_errors, :erase_all],
      default: :retain_all

    field :history_retention_period, :integer
    field :dataclip_retention_period, :integer

    has_many :project_users, ProjectUser
    has_many :users, through: [:project_users, :user]
    has_many :project_credentials, ProjectCredential
    has_many :credentials, through: [:project_credentials, :credential]

    has_many :workflows, Workflow
    has_many :jobs, through: [:workflows, :jobs]

    timestamps()
  end

  @doc false
  # TODO: schedule_deletion shouldn't be changed by user input
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :scheduled_deletion,
      :requires_mfa,
      :retention_policy,
      :history_retention_period,
      :dataclip_retention_period
    ])
    |> cast_assoc(:project_users)
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> validate_length(:description, max: 240)
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-z\-\d]+$/)
    |> validate_inclusion(:history_retention_period, @retention_periods)
    |> validate_inclusion(:dataclip_retention_period, @retention_periods)
    |> validate_dataclip_retention_period()
  end

  defp validate_dataclip_retention_period(changeset) do
    history_retention_period = get_field(changeset, :history_retention_period)

    changeset =
      if is_nil(history_retention_period) or
           get_field(changeset, :retention_policy) == :erase_all do
        put_change(changeset, :dataclip_retention_period, nil)
      else
        changeset
      end

    dataclip_retention_period = get_change(changeset, :dataclip_retention_period)

    changeset =
      if dataclip_retention_period do
        validate_required(changeset, [:history_retention_period])
      else
        changeset
      end

    if changeset.valid? and is_integer(dataclip_retention_period) and
         dataclip_retention_period > history_retention_period do
      add_error(
        changeset,
        :dataclip_retention_period,
        "dataclip retention period must be less or equal to the history retention period"
      )
    else
      changeset
    end
  end

  @doc """
  Changeset to validate a project deletion request, the user must enter the
  projects name to confirm.
  """
  def deletion_changeset(project, attrs) do
    project
    |> cast(attrs, [:name])
    |> validate_confirmation(:name, message: "doesn't match the project name")
  end
end
