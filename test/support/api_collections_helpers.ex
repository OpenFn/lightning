defmodule LightningWeb.ApiCollectionsHelpers do
  @moduledoc """
  Setup shared by the `/collections` item API tests.
  """
  import Lightning.Factories

  alias LightningWeb.ConnHelpers

  @doc """
  A `setup` callback giving a member of a project, the project, an empty
  collection in it, and `conn` carrying the member's personal access token.

  The member is a plain project member unless the test sets the `:role` tag.
  """
  def member_with_collection(%{conn: conn} = context) do
    user = insert(:user)

    project_user =
      case context[:role] do
        nil -> %{user: user}
        role -> %{user: user, role: role}
      end

    project = insert(:project, project_users: [project_user])
    collection = insert(:collection, project: project)

    %{
      conn: ConnHelpers.assign_bearer(conn, user),
      user: user,
      project: project,
      collection: collection
    }
  end

  @doc """
  The run token of a run in `project`, or in a new project when none is given.
  """
  def run_token(project \\ nil) do
    workflow =
      if project,
        do: insert(:simple_workflow, project: project),
        else: insert(:simple_workflow)

    workorder =
      insert(:workorder, workflow: workflow, dataclip: insert(:dataclip))

    run =
      insert(:run,
        work_order: workorder,
        dataclip: workorder.dataclip,
        starting_trigger: hd(workflow.triggers)
      )

    Lightning.Workers.generate_run_token(run)
  end
end
