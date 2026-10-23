defmodule Lightning.RaceHelpers do
  @moduledoc """
  Makes another request's write land in the middle of the one under test.
  """

  alias Lightning.Repo

  @doc """
  Calls `fun` with the dumped `id` the first time `pid` runs a query on the
  table `source` with `id` among its parameters, and never again.

  Use it to delete or bump a row after the code under test has read it and
  before it writes. Only queries from `pid` count, because other async tests
  query from their own processes. The handler is detached when the test exits.

  A raise is what Sentry reports, and ConnTest hands a raise to the test, so a
  conn test that reaches its assertion shows nothing was reported.

      after_first_query("users", user.id, fn id ->
        Repo.query!("DELETE FROM users WHERE id = $1", [id])
      end)
  """
  def after_first_query(source, id, fun, pid \\ self()) do
    handler = {__MODULE__, make_ref()}
    dumped = Ecto.UUID.dump!(id)

    :telemetry.attach(
      handler,
      [:lightning, :repo, :query],
      fn _event, _measurements, meta, _config ->
        if self() == pid and meta.source == source and
             dumped in List.flatten(meta.params) and
             not Process.get(handler, false) do
          Process.put(handler, true)
          fun.(dumped)
        end
      end,
      nil
    )

    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler) end)
  end

  @doc """
  Deletes the project `project_id` after `pid` first queries `projects` for it,
  which is after the save has read the project and before it writes.
  """
  def delete_project_mid_save(project_id, pid \\ self()) do
    after_first_query(
      "projects",
      project_id,
      fn id ->
        Repo.query!("DELETE FROM project_users WHERE project_id = $1", [id])
        Repo.query!("DELETE FROM projects WHERE id = $1", [id])
      end,
      pid
    )
  end

  @doc """
  Bumps the `lock_version` of the workflow `workflow_id` after `pid` first
  queries `workflows` for it, so the save under test loses the race.
  """
  def bump_workflow_lock_mid_save(workflow_id, pid \\ self()) do
    after_first_query(
      "workflows",
      workflow_id,
      fn id ->
        Repo.query!(
          "UPDATE workflows SET lock_version = lock_version + 1 WHERE id = $1",
          [id]
        )
      end,
      pid
    )
  end
end
