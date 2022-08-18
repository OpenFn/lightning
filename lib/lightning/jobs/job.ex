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
  alias Lightning.Projects.{Project, ProjectCredential}

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          body: String.t() | nil,
          enabled: boolean(),
          name: String.t() | nil,
          adaptor: String.t() | nil,
          trigger: nil | Trigger.t() | Ecto.Association.NotLoaded.t(),
          credential: nil | Credential.t() | Ecto.Association.NotLoaded.t(),
          project: nil | Project.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "jobs" do
    field :body, :string
    field :enabled, :boolean, default: false
    field :name, :string
    field :adaptor, :string

    has_one :trigger, Trigger
    has_many :events, Lightning.Invocation.Event

    # belongs_to :credential, Credential
    belongs_to :project_credential, ProjectCredential
    has_one :credential, through: [:project_credential, :credential]
    belongs_to :project, Project

    timestamps()
  end

  @doc false
  def changeset(job, attrs) do
    job
    |> cast(attrs, [
      :name,
      :body,
      :enabled,
      :adaptor,
      :project_credential_id,
      :project_id
    ])
    |> cast_assoc(:trigger, with: &Trigger.changeset/2, required: true)
    |> validate_required([:name, :body, :enabled, :adaptor, :project_id])
    |> validate_length(:name, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/)
  end
end
