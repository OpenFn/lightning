defmodule Lightning.Projects.Environment do
  @moduledoc """
  Which environment a project resolves its credentials in.

  A credential can hold a body per environment, and the environment name is what
  selects between them. Anything reaching for a credential body therefore has to
  answer this question first, and every caller answering it differently is how
  two of them ended up hard-coding `"main"` and handing sandbox members the
  parent project's production secret.

  This is that answer, in one place. It fails closed: a sandbox with no
  environment set gets an error rather than a guess, because guessing here means
  guessing which secret to hand over.
  """

  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Run

  # The map member is deliberately open: a closed `%{project_id: Ecto.UUID.t()}`
  # puts the channel struct this clause exists for out of contract.
  @type subject ::
          Project.t()
          | Run.t()
          | Ecto.UUID.t()
          | %{project_id: Ecto.UUID.t()}
          | nil

  @type error :: :environment_not_configured | :project_not_found

  @doc """
  The environment for whatever you have in hand.

  Takes a project, a run, a project id, or any struct carrying a `project_id`,
  so a caller does not have to load a project it does not otherwise need. That
  matters at the channel proxy, which holds a channel and never preloads its
  project.
  """
  @spec fetch(subject()) :: {:ok, String.t()} | {:error, error()}
  def fetch(%Project{} = project), do: from_project(project)

  def fetch(%Run{} = run) do
    run
    |> Lightning.Projects.get_project_for_run()
    |> from_project()
  end

  # Repo.get raises Ecto.Query.CastError on a malformed binary_id, which turns a
  # refusal into a 500. Cast first, the same way `Projects.Scope` does.
  def fetch(project_id) when is_binary(project_id) do
    case Ecto.UUID.cast(project_id) do
      {:ok, uuid} -> Project |> Repo.get(uuid) |> from_project()
      :error -> {:error, :project_not_found}
    end
  end

  def fetch(%{project_id: project_id}) when is_binary(project_id) do
    fetch(project_id)
  end

  def fetch(_no_project), do: {:error, :project_not_found}

  # A root project that predates the environment column is the one case where a
  # default is honest: it has always resolved against "main" and nothing above
  # it can be shadowed. A sandbox without one is a different matter, since the
  # name is what stands between it and its parent's credentials.
  #
  # Deliberately silent. This is now asked on every metadata fetch and every
  # channel request, not once per run, and callers that treat the outcome as a
  # failure log it themselves. See .claude/rules/logging.md on single log sites.
  defp from_project(%Project{env: nil, parent_id: nil}), do: {:ok, "main"}

  defp from_project(%Project{env: env}) when is_binary(env), do: {:ok, env}

  defp from_project(%Project{env: nil}) do
    {:error, :environment_not_configured}
  end

  defp from_project(nil), do: {:error, :project_not_found}
end
