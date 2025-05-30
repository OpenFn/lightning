defmodule Lightning.VersionControl.ProjectRepoConnection do
  @moduledoc """
  Ecto model for project repo connections
  """

  use Lightning.Schema

  alias Lightning.Projects.Project

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          github_installation_id: String.t() | nil,
          repo: String.t() | nil,
          branch: String.t() | nil,
          project: nil | Project.t() | Ecto.Association.NotLoaded
        }

  schema "project_repo_connections" do
    field :github_installation_id, :string
    field :repo, :string
    field :branch, :string
    field :access_token, :binary
    field :config_path, :string
    field :accept, :boolean, virtual: true

    field :sync_direction, Ecto.Enum,
      values: [:deploy, :pull],
      virtual: true,
      default: :pull

    belongs_to :project, Project

    timestamps()
  end

  defmodule AccessToken do
    @moduledoc false

    use Joken.Config

    @impl true
    def token_config do
      default_claims(skip: [:exp, :aud], iss: "Lightning")
      |> add_claim(
        "iat",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        &(Lightning.current_time() |> DateTime.to_unix() >= &1)
      )
      |> add_claim(
        "nbf",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        &(Lightning.current_time() |> DateTime.to_unix() >= &1)
      )
    end
  end

  @required_fields ~w(github_installation_id repo branch project_id)a
  @other_fields ~w(config_path)a

  def changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> cast(attrs, @required_fields ++ @other_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:project_id,
      message: "project already has a repo connection"
    )
  end

  def configure_changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> changeset(attrs)
    |> cast(attrs, [:sync_direction, :accept])
    |> validate_required([:sync_direction, :accept])
    |> validate_change(:accept, fn :accept, accept ->
      if accept do
        []
      else
        [accept: "please tick the box"]
      end
    end)
    |> validate_sync_direction()
  end

  def reconfigure_changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> cast(attrs, [:sync_direction, :accept])
    |> validate_required([:sync_direction, :accept])
    |> validate_sync_direction()
  end

  def create_changeset(project_repo_connection, attrs) do
    changeset = configure_changeset(project_repo_connection, attrs)

    if changeset.valid? do
      project_id = get_field(changeset, :project_id)

      put_change(changeset, :access_token, generate_access_token(project_id))
    else
      changeset
    end
  end

  defp validate_sync_direction(changeset) do
    validate_change(changeset, :sync_direction, fn _field, value ->
      path = get_field(changeset, :config_path)

      if value == :deploy and is_nil(path) do
        [config_path: "you must specify a path to an existing config file"]
      else
        []
      end
    end)
  end

  defp generate_access_token(project_id) do
    {:ok, token, _claims} =
      AccessToken.generate_and_sign(
        %{"project_id" => project_id},
        Lightning.Config.repo_connection_token_signer()
      )

    token
  end

  def config_path(repo_connection) do
    repo_connection.config_path ||
      "./openfn-#{repo_connection.project_id}-config.json"
  end
end
