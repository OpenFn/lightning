defmodule Lightning.VersionControl.ProjectRepoConnection do
  @moduledoc """
  Ecto model for project repo connections
  """

  use Lightning.Schema

  import Ecto.Query

  alias Lightning.Projects.Project
  alias Lightning.Repo

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
    field :sync_version, :boolean, default: false
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
  @other_fields ~w(config_path sync_version)a

  def changeset(project_repo_connection, attrs) do
    project_repo_connection
    |> cast(attrs, @required_fields ++ @other_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:project_id,
      message: "project already has a repo connection"
    )
    |> validate_no_ancestor_branch_conflict()
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

  defp validate_no_ancestor_branch_conflict(changeset) do
    project_id = get_field(changeset, :project_id)
    repo = get_field(changeset, :repo)
    branch = get_field(changeset, :branch)

    if is_binary(project_id) and is_binary(repo) and is_binary(branch) do
      ancestor_ids = Lightning.Projects.ancestor_ids(project_id)

      if ancestor_ids != [] and
           ancestor_branch_conflict?(ancestor_ids, repo, branch) do
        add_error(
          changeset,
          :branch,
          "this branch is already linked to a parent project; sandboxes must use a different branch"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  @doc false
  @spec ancestor_branch_conflict?([Ecto.UUID.t()], String.t(), String.t()) ::
          boolean()
  def ancestor_branch_conflict?([], _repo, _branch), do: false

  def ancestor_branch_conflict?(ancestor_ids, repo, branch)
      when is_list(ancestor_ids) and is_binary(repo) and is_binary(branch) do
    Repo.exists?(
      from(c in __MODULE__,
        where: c.project_id in ^ancestor_ids,
        where: c.repo == ^repo,
        where: c.branch == ^branch
      )
    )
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
      if repo_connection.sync_version do
        path_to_openfn_yaml()
      else
        "./openfn-#{repo_connection.project_id}-config.json"
      end
  end

  def path_to_openfn_yaml do
    "openfn.yaml"
  end
end
