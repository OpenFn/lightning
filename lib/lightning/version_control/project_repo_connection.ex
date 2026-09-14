defmodule Lightning.VersionControl.ProjectRepoConnection do
  @moduledoc """
  Ecto model for project repo connections
  """

  use Lightning.Schema

  import Ecto.Query

  alias Lightning.Projects.Project
  alias Lightning.Repo

  @tree_branch_error "this branch is already linked to another project in the same project family; use a different branch"
  @tree_unique_index "project_repo_connections_root_repo_branch_index"

  @type t() :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          github_installation_id: String.t() | nil,
          repo: String.t() | nil,
          branch: String.t() | nil,
          root_project_id: Ecto.UUID.t() | nil,
          project: nil | Project.t() | Ecto.Association.NotLoaded
        }

  schema "project_repo_connections" do
    field :github_installation_id, :string
    field :repo, :string
    field :branch, :string
    field :access_token, :binary
    field :config_path, :string
    field :sync_version, :boolean, default: false
    field :root_project_id, Ecto.UUID
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
    |> put_root_project_id()
    |> unique_constraint(:project_id,
      message: "project already has a repo connection"
    )
    |> unique_constraint(:branch,
      name: @tree_unique_index,
      message: @tree_branch_error
    )
    |> validate_no_tree_branch_conflict()
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

  defp put_root_project_id(changeset) do
    case get_field(changeset, :root_project_id) do
      nil ->
        with project_id when is_binary(project_id) <-
               get_field(changeset, :project_id),
             root_id when is_binary(root_id) <-
               Lightning.Projects.root_id(project_id) do
          put_change(changeset, :root_project_id, root_id)
        else
          _ -> changeset
        end

      _ ->
        changeset
    end
  end

  defp validate_no_tree_branch_conflict(changeset) do
    root_project_id = get_field(changeset, :root_project_id)
    repo = get_field(changeset, :repo)
    branch = get_field(changeset, :branch)
    self_id = get_field(changeset, :id)

    if is_binary(root_project_id) and is_binary(repo) and is_binary(branch) do
      if tree_branch_conflict?(root_project_id, repo, branch, self_id) do
        add_error(changeset, :branch, @tree_branch_error,
          reason: :tree_branch_conflict
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  @doc """
  Returns `true` when any other connection already binds the given
  `(repo, branch)` to the same project tree (identified by `root_project_id`).
  Excludes the row identified by `self_id` so that updates to an existing
  connection don't conflict with themselves.
  """
  @spec tree_branch_conflict?(
          Ecto.UUID.t(),
          String.t(),
          String.t(),
          Ecto.UUID.t() | nil
        ) :: boolean()
  def tree_branch_conflict?(root_project_id, repo, branch, self_id \\ nil)
      when is_binary(root_project_id) and is_binary(repo) and is_binary(branch) do
    base =
      from(c in __MODULE__,
        where: c.root_project_id == ^root_project_id,
        where: c.repo == ^repo,
        where: c.branch == ^branch
      )

    query =
      if is_binary(self_id) do
        from c in base, where: c.id != ^self_id
      else
        base
      end

    Repo.exists?(query)
  end

  @doc """
  True if the given changeset's insert/update failed on the tree-uniqueness
  index. Used to translate a constraint violation back into the
  `:branch_used_in_project_tree` atom error at the boundary.
  """
  @spec tree_unique_violation?(Ecto.Changeset.t()) :: boolean()
  def tree_unique_violation?(%Ecto.Changeset{errors: errors}) do
    Enum.any?(errors, fn
      {:branch, {_msg, opts}} ->
        Keyword.get(opts, :constraint) == :unique and
          Keyword.get(opts, :constraint_name) == @tree_unique_index

      _ ->
        false
    end)
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
