defmodule LightningWeb.ApiCollectionsHelpers do
  @moduledoc """
  Setup shared by the `/collections` item API tests.
  """
  use LightningWeb, :verified_routes

  import Lightning.Factories
  import Phoenix.ConnTest, only: [get: 2, put: 3, post: 3, delete: 2]

  alias LightningWeb.ConnHelpers

  @endpoint LightningWeb.Endpoint

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
  One request to each `/collections` route on the collection `name`, as
  `{verb, request}` pairs whose `request` takes a conn. The key routes use the
  key `k`.
  """
  def routes_for(name) do
    [
      get: &get(&1, ~p"/collections/#{name}"),
      get: &get(&1, ~p"/collections/#{name}/k"),
      put: &put(&1, ~p"/collections/#{name}/k", %{value: "v"}),
      post:
        &post(&1, ~p"/collections/#{name}", %{items: [%{key: "k", value: "v"}]}),
      delete: &delete(&1, ~p"/collections/#{name}/k"),
      delete: &delete(&1, ~p"/collections/#{name}")
    ]
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
