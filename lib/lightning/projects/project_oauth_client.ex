defmodule Lightning.Projects.ProjectOauthClient do
  @moduledoc """
  Manages the relationship between OAuth clients and projects, acting as a join table.
  This module defines the schema and validations needed for creating and managing
  associations between `OauthClient` and `Project`. It ensures that an OAuth client
  can be associated with a project, facilitating the management of access permissions
  and settings specific to a project.

  ## Schema Information

  The schema represents the bridge between projects and OAuth clients with the following fields:

  - `:id`: The unique identifier for the association, automatically generated.
  - `:oauth_client_id`: Foreign key to link with the OAuth client.
  - `:project_id`: Foreign key to link with the project.

  This module also includes a virtual field `:delete` to mark an association for deletion,
  aiding in operations that require soft deletion patterns or special handling before
  actually removing an association.

  ## Usage

  The primary function of this module is to create and manage changesets for adding or
  removing OAuth clients from projects, ensuring data integrity and enforcing business
  rules such as uniqueness of the association.
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
  schema "project_oauth_clients" do
    belongs_to :oauth_client, OauthClient
    belongs_to :project, Project
    field :delete, :boolean, virtual: true, default: false

    timestamps()
  end

  @doc false
  def changeset(project_oauth_client, %{"delete" => "true"}) do
    %{change(project_oauth_client, delete: true) | action: :delete}
  end

  @doc """
  Creates or updates changesets for a `ProjectOauthClient` entity based on the given attributes.
  Validates required fields and applies a unique constraint to ensure an OAuth client
  can be associated with a project only once.

  This changeset is used for adding new or updating existing associations between an OAuth client and a project.
  """
  def changeset(project_oauth_client, attrs) do
    project_oauth_client
    |> cast(attrs, [:oauth_client_id, :project_id, :delete])
    |> validate_required([:project_id])
    |> unique_constraint([:project_id, :oauth_client_id],
      message: "oauth client already added to this project."
    )
  end
end
