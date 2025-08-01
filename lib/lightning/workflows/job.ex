defmodule Lightning.Workflows.Job do
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
  """
  use Lightning.Schema

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Validators
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: String.t() | nil,
          name: String.t() | nil,
          adaptor: String.t() | nil,
          credential: nil | Credential.t() | Ecto.Association.NotLoaded.t(),
          keychain_credential:
            nil | KeychainCredential.t() | Ecto.Association.NotLoaded.t(),
          workflow: nil | Workflow.t() | Ecto.Association.NotLoaded.t()
        }

  @derive {Jason.Encoder,
           only: [
             :id,
             :body,
             :name,
             :adaptor
           ]}
  schema "jobs" do
    field :body, :string

    field :name, :string
    field :adaptor, :string, default: "@openfn/language-common@latest"

    belongs_to :project_credential, ProjectCredential
    has_one :credential, through: [:project_credential, :credential]

    belongs_to :keychain_credential, KeychainCredential

    belongs_to :workflow, Workflow
    has_one :project, through: [:workflow, :project]

    has_many :steps, Lightning.Invocation.Step

    field :delete, :boolean, virtual: true

    timestamps(type: :utc_datetime_usec)
  end

  def new(attrs \\ %{}) do
    change(%__MODULE__{}, Map.merge(%{id: Ecto.UUID.generate()}, attrs))
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :id,
      # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
      :inserted_at,
      :name,
      :body,
      :adaptor,
      :project_credential_id,
      :keychain_credential_id,
      :workflow_id
    ])
    |> validate()
    |> update_change(:name, &String.trim/1)
    |> unique_constraint(:name,
      name: "jobs_name_workflow_id_index",
      message: "job name has already been taken"
    )
    |> unique_constraint(:id, name: "jobs_pkey")
  end

  def validate(changeset) do
    changeset
    |> validate_required(:name, message: "job name can't be blank")
    |> validate_required(:body, message: "job body can't be blank")
    |> validate_required(:adaptor, message: "job adaptor can't be blank")
    |> Validators.validate_exclusive(
      [:project_credential_id, :keychain_credential_id],
      "cannot be set when the other credential type is also set"
    )
    |> validate_keychain_credential_project_membership()
    |> foreign_key_constraint(:project_credential_id,
      message: "credential doesn't exist or isn't available in this project"
    )
    |> foreign_key_constraint(:keychain_credential_id,
      message: "keychain credential doesn't exist"
    )
    |> assoc_constraint(:workflow)
    |> validate_length(:name,
      max: 100,
      message: "job name should be at most %{count} character(s)"
    )
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/,
      message: "job name has invalid format"
    )
  end

  defp validate_keychain_credential_project_membership(changeset) do
    keychain_credential_id = get_field(changeset, :keychain_credential_id)
    workflow_id = get_field(changeset, :workflow_id)

    if keychain_credential_id && workflow_id do
      case Lightning.Repo.get(Lightning.Workflows.Workflow, workflow_id) do
        %{project_id: project_id} ->
          case Lightning.Repo.get_by(
                 Lightning.Credentials.KeychainCredential,
                 id: keychain_credential_id,
                 project_id: project_id
               ) do
            nil ->
              add_error(
                changeset,
                :keychain_credential_id,
                "must belong to the same project as the job"
              )

            _ ->
              changeset
          end

        nil ->
          changeset
      end
    else
      changeset
    end
  end

  @doc """
  Attaches a workflow to a job, this is useful when you have an unpersisted
  Workflow changeset - and want it to be created at the same time as a Job.


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
