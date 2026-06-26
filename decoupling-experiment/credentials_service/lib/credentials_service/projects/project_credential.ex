defmodule CredentialsService.Projects.ProjectCredential do
  @moduledoc """
  The `projects` <-> `credentials` join. This is how a credential is scoped to a
  project: there is NO `credentials.project_id` column. This join table is the
  seam the extraction cuts along, so the Credentials service owns it. `project_id`
  is an opaque id pointing at the Projects service.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias CredentialsService.Credentials.Credential

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "project_credentials" do
    field :project_id, :binary_id

    belongs_to :credential, Credential

    timestamps()
  end

  @doc false
  def changeset(project_credential, attrs) do
    project_credential
    |> cast(attrs, [:project_id, :credential_id])
    |> validate_required([:project_id])
  end
end
