defmodule Lightning.Projects.Project do
  @moduledoc """
  Project model
  """
  use Lightning.Schema

  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectOauthClient
  alias Lightning.Projects.ProjectUser
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          project_users: [ProjectUser.t()] | Ecto.Association.NotLoaded.t()
        }

  @type retention_policy_type :: :retain_all | :retain_with_errors | :erase_all

  schema "projects" do
    field :name, :string
    field :allow_support_access, :boolean, default: false
    field :concurrency, :integer
    field :description, :string
    field :scheduled_deletion, :utc_datetime
    field :requires_mfa, :boolean, default: false

    field :retention_policy, Ecto.Enum,
      values: [:retain_all, :retain_with_errors, :erase_all],
      default: :retain_all

    field :history_retention_period, :integer
    field :dataclip_retention_period, :integer

    field :color, :string
    field :env, :string

    belongs_to :parent, __MODULE__, type: :binary_id

    has_many :project_users, ProjectUser
    has_many :users, through: [:project_users, :user]
    has_many :project_oauth_clients, ProjectOauthClient
    has_many :oauth_clients, through: [:project_oauth_clients, :oauth_client]
    has_many :sandboxes, __MODULE__, foreign_key: :parent_id

    has_many :workflows, Workflow, where: [deleted_at: nil]
    has_many :jobs, through: [:workflows, :jobs]

    has_many :project_credentials, ProjectCredential
    has_many :credentials, through: [:project_credentials, :credential]

    has_many :collections, Lightning.Collections.Collection

    timestamps()
  end

  @spec data_retention_options() :: [pos_integer(), ...]
  def data_retention_options do
    [7, 14, 30, 90, 180, 365]
  end

  @doc false
  # TODO: schedule_deletion shouldn't be changed by user input
  def changeset(project, attrs) do
    project
    |> cast(attrs, [
      :id,
      :name,
      :concurrency,
      :description,
      :scheduled_deletion,
      :requires_mfa,
      :retention_policy,
      :history_retention_period,
      :dataclip_retention_period,
      :allow_support_access,
      :parent_id,
      :color,
      :env
    ])
    |> set_default_env_for_root_projects()
    |> validate()
  end

  defp set_default_env_for_root_projects(changeset) do
    parent_id = get_field(changeset, :parent_id)
    env = get_field(changeset, :env)

    if is_nil(parent_id) && is_nil(env) do
      put_change(changeset, :env, "main")
    else
      changeset
    end
  end

  def validate(changeset) do
    changeset
    |> validate_length(:description, max: 240)
    |> validate_required([:name])
    |> validate_format(:name, ~r/^[a-z\-\d]+$/)
    |> validate_dataclip_retention_period()
    |> validate_inclusion(:history_retention_period, data_retention_options())
    |> validate_inclusion(:dataclip_retention_period, data_retention_options())
    |> validate_format(
      :color,
      ~r/^#([A-Fa-f0-9]{6}|[A-Fa-f0-9]{3}|[A-Fa-f0-9]{8})$/,
      message: "must be hex",
      allow_nil: true
    )
    |> validate_format(:env, ~r/^[a-z0-9][a-z0-9_-]{0,31}$/,
      message: "must be a short slug",
      allow_nil: true
    )
    |> unique_constraint(:name, name: "projects_unique_child_name")
    |> disallow_self_parent()
  end

  defp disallow_self_parent(%{data: %{id: nil}} = changeset), do: changeset

  defp disallow_self_parent(changeset) do
    if get_field(changeset, :parent_id) == changeset.data.id,
      do: add_error(changeset, :parent_id, "cannot be self"),
      else: changeset
  end

  @doc """
  Returns `true` if the project is a sandbox (i.e. `parent_id` is a UUID),
  `false` otherwise.
  """
  @spec sandbox?(t()) :: boolean()
  def sandbox?(%__MODULE__{parent_id: pid}) when is_binary(pid), do: true
  def sandbox?(_), do: false

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

  def project_with_users_changeset(project, attrs) do
    project
    |> cast(attrs, [
      :id,
      :name,
      :description,
      :concurrency,
      :parent_id,
      :color,
      :env
    ])
    |> cast_assoc(:project_users, required: true, sort_param: :users_sort)
    |> validate()
    |> validate_project_owner()
  end

  defp validate_project_owner(changeset) do
    changeset
    |> get_assoc(:project_users)
    |> Enum.count(fn project_user ->
      get_field(project_user, :role) == :owner
    end)
    |> case do
      1 ->
        changeset

      0 ->
        add_error(
          changeset,
          :owner,
          "Every project must have exactly one owner. Please specify one below."
        )

      _more_than_1 ->
        add_error(changeset, :owner, "A project can have only one owner.")
    end
  end
end
