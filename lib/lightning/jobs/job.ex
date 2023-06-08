defmodule Lightning.Jobs.Job do
  @moduledoc """
  Ecto model for Jobs.

  A Job contains the fields for defining a job.

  * `body`
    The expression/javascript code
  * `name`
    A plain text identifier
  * `adaptor`
    An NPM style string that contains both the module name and it's version.
    E.g. `@openfn/language-http@v1.2.3` or `@openfn/language-foo@latest`.
    While the version suffix isn't enforced here as it's not strictly necessary
    in this context, the front end will ensure a version is stated (`@latest`
    being the default).
  * `trigger`
    Association to it's trigger, a job _must_ have a trigger.
    See `Lightning.Jobs.Trigger`.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Jobs.Trigger
  alias Lightning.Credentials.Credential
  alias Lightning.Workflows.Workflow
  alias Lightning.Projects.{ProjectCredential}

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: String.t() | nil,
          enabled: boolean(),
          name: String.t() | nil,
          adaptor: String.t() | nil,
          trigger: nil | Trigger.t() | Ecto.Association.NotLoaded.t(),
          credential: nil | Credential.t() | Ecto.Association.NotLoaded.t(),
          workflow: nil | Workflow.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "jobs" do
    field :body, :string

    field :enabled, :boolean, default: true
    field :name, :string
    field :adaptor, :string, default: "@openfn/language-common@latest"
    belongs_to :trigger, Trigger

    belongs_to :project_credential, ProjectCredential
    has_one :credential, through: [:project_credential, :credential]
    belongs_to :workflow, Workflow
    has_one :project, through: [:workflow, :project]

    field :delete, :boolean, virtual: true

    timestamps()
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, attrs)
  end

  @doc false
  def changeset(job, attrs) do
    change =
      job
      |> cast(attrs, [
        :id,
        :name,
        :body,
        :enabled,
        :adaptor,
        :project_credential_id,
        :workflow_id,
        :trigger_id
      ])

    change
    |> cast_assoc(:trigger,
      with: {Trigger, :changeset, [change |> get_field(:workflow_id)]}
    )
    |> validate()
  end

  # DEPRECATED: Jobs are now created via the workflow, this function is only
  # used when creating a Job via a Trigger.
  # Uncomment if this causes issues before fully removing other changeset/3
  # functions.
  # def changeset(job, attrs, workflow_id) do
  #   attrs = Map.put(attrs, :workflow_id, workflow_id)
  #
  #   job
  #   |> changeset(attrs)
  #   |> validate_required(:workflow_id)
  # end

  def validate(changeset) do
    changeset
    |> validate_required([
      :name,
      :body,
      :enabled,
      :adaptor
    ])
    |> assoc_constraint(:trigger)
    |> assoc_constraint(:workflow)
    |> validate_length(:name, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/)
  end

  @doc """
  Attaches a workflow to a job, this is useful when you have an unpersisted
  Workflow changeset - and want it to be created at the same time as a Job.

  Be sure to pass the return of this function into `changeset/2` in order to
  have this jobs trigger get the workflows id.

  Example:

      workflow =
        Ecto.Changeset.cast(
          %Lightning.Workflows.Workflow{},
          %{ "project_id" => attrs[:project_id], "id" => Ecto.UUID.generate() },
          [:project_id, :id]
        )

      job =
        %Job{}
        |> Ecto.Changeset.change()
        |> Job.put_workflow(workflow)
        |> Job.changeset(attrs)

  """
  @spec put_workflow(
          Ecto.Changeset.t(__MODULE__.t()),
          Ecto.Changeset.t(Workflow.t())
        ) ::
          Ecto.Changeset.t(__MODULE__.t())
  def put_workflow(%Ecto.Changeset{} = changeset, %Ecto.Changeset{} = workflow) do
    changeset
    |> Ecto.Changeset.put_change(
      :workflow_id,
      workflow |> Ecto.Changeset.get_field(:id)
    )
    |> Ecto.Changeset.put_assoc(:workflow, workflow)
  end

  def put_project_credential(job, project_credential) do
    job
    |> Ecto.Changeset.put_assoc(:project_credential, project_credential)
  end
end
