defmodule Lightning.Release do
  @moduledoc """
  Used for executing DB release tasks when run in production without Mix
  installed.

  ## One-off cutover task

  `backfill_deleted_workflow_names/1` frees the names of workflows that were
  soft-deleted before merges renamed on delete. Run it once, on the release
  that ships that fix, via `bin/backfill_deleted_workflow_names`. It is
  idempotent and is removed in the follow-up cleanup PR.
  """

  import Ecto.Query

  require Logger

  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow

  @app :lightning
  @repo Lightning.Repo

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def create_db do
    @repo.__adapter__().storage_up(@repo.config)
    |> case do
      :ok ->
        Logger.info("Database created successfully")
        :ok

      {:error, :already_up} ->
        Logger.info("Database already up.")
        :ok

      {:error, e} ->
        Logger.error("Encountered an error during database creation")
        Logger.error(e)
        {:error, e}
    end
  end

  def rollback(repo, version) do
    load_app()

    {:ok, _, _} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  def load_app do
    Application.ensure_all_started(:ssl)
    Application.ensure_all_started(@repo)
  end

  @doc """
  One-off cutover task: frees the names of soft-deleted workflows that still
  hold their original `(name, project_id)`.

  Workflows soft-deleted before merges renamed on delete keep their original
  name, which the uniqueness rule then uses to block a later merge from
  recreating that name. This renames each to `name_del`/`name_delN`, the same
  scheme UI and merge deletes now use, reusing
  `Workflows.resolve_name_for_pending_deletion/1` so the freed names match.

  Idempotent: only touches names that aren't already `_del`-suffixed, and each
  rename is committed before the next so collision-avoidance sees it. Safe to
  re-run if interrupted. Pass `dry_run: true` to log the count without writing.

  Removed in the follow-up cleanup PR once the cutover has run.
  """
  @spec backfill_deleted_workflow_names(keyword()) :: {:ok, non_neg_integer()}
  def backfill_deleted_workflow_names(opts \\ []) do
    start_repo()

    targets =
      from(w in Workflow,
        where:
          not is_nil(w.deleted_at) and fragment("? !~ '_del[0-9]*$'", w.name)
      )
      |> @repo.all()

    if Keyword.get(opts, :dry_run, false) do
      Logger.info(
        "[dry run] #{length(targets)} soft-deleted workflow name(s) would be freed"
      )

      {:ok, length(targets)}
    else
      Enum.each(targets, &free_workflow_name/1)

      Logger.info(
        "Freed #{length(targets)} soft-deleted workflow name(s). Safe to re-run."
      )

      {:ok, length(targets)}
    end
  end

  defp free_workflow_name(%Workflow{} = workflow) do
    new_name = Workflows.resolve_name_for_pending_deletion(workflow)

    from(w in Workflow, where: w.id == ^workflow.id)
    |> @repo.update_all(
      set: [
        name: new_name,
        updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
      ]
    )
  end

  defp start_repo do
    load_app()
    {:ok, _} = Application.ensure_all_started(:ecto_sql)

    case @repo.start_link(pool_size: 2) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end
end
