defmodule Lightning.Projects.ProjectOauthClient do
  @moduledoc """
  Join table to assign oauth clients to a project
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.Project

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          oauth_client: OauthClient.t() | Ecto.Association.NotLoaded.t() | nil,
          project: Project.t() | Ecto.Association.NotLoaded.t() | nil
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "project_credentials" do
    belongs_to :oauth_client, OauthClient
    belongs_to :project, Project

    timestamps()
  end

  @doc false
  def changeset(project_oauth_client, attrs) do
    project_oauth_client
    |> cast(attrs, [:oauth_client_id, :project_id])
    |> validate_required([:project_id])
    |> unique_constraint([:project_id, :oauth_client_id],
      message: "oauth client already added to this project."
    )
  end
end
