defmodule LightningWeb.API.WebhookAuthMethods.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  alias Lightning.Repo
  alias Lightning.Workflows.WebhookAuthMethod

  @body %{"name" => "x", "auth_type" => "api", "x" => 1}

  defp reach(conn, :index, project_id, nil),
    do: get(conn, "/api/projects/#{project_id}/webhook_auth_methods")

  defp reach(conn, :get, project_id, id),
    do: get(conn, "/api/projects/#{project_id}/webhook_auth_methods/#{id}")

  defp reach(conn, :put, project_id, id),
    do:
      send_json(
        conn,
        :put,
        "/api/projects/#{project_id}/webhook_auth_methods/#{id}",
        @body
      )

  defp reach(conn, :delete, project_id, id),
    do: delete(conn, "/api/projects/#{project_id}/webhook_auth_methods/#{id}")

  test "a caller the project refuses gets the same 403 for every id, and an owner or admin hears what is missing, malformed or held elsewhere",
       %{conn: conn} do
    c = callers()
    pat = &with_pat(conn, &1)
    unknown = Ecto.UUID.generate()
    elsewhere = insert(:webhook_auth_method, name: "elsewhere")
    malformed_id = [not_a_uuid_entry(%{"path" => "id"})]

    refused =
      for {user, project} <- [
            {c.stranger, c.project},
            {c.editor, c.project},
            {c.viewer, c.project},
            {c.superuser, c.project},
            {c.short_of_mfa, c.mfa_project},
            {c.stranger, c.scheduled}
          ],
          id <- [
            insert(:webhook_auth_method, project: project).id,
            unknown,
            "not-a-uuid",
            elsewhere.id
          ],
          verb <- [:get, :put, :delete],
          do: {pat.(user), verb, project.id, id, 403, :forbidden, []}

    refused_lists =
      for {user, project} <- [
            {c.stranger, c.project},
            {c.superuser, c.project},
            {c.short_of_mfa, c.mfa_project},
            {c.stranger, c.scheduled}
          ],
          do: {pat.(user), :index, project.id, nil, 403, :forbidden, []}

    permitted =
      for user <- [c.owner, c.admin],
          {verb, id, status, code, entries} <- [
            {:get, unknown, 404, :not_found, []},
            {:get, elsewhere.id, 404, :not_found, []},
            {:get, "not-a-uuid", 400, :invalid_parameter, malformed_id},
            {:put, "not-a-uuid", 400, :invalid_parameter, malformed_id},
            {:put, elsewhere.id, 409, :id_taken, []},
            {:delete, unknown, 404, :not_found, []},
            {:delete, elsewhere.id, 404, :not_found, []},
            {:delete, "not-a-uuid", 400, :invalid_parameter, malformed_id}
          ],
          do: {pat.(user), verb, c.project.id, id, status, code, entries}

    projects =
      for {project_id, superuser_answer} <- [
            {Ecto.UUID.generate(), {404, :not_found, []}},
            {"not-a-uuid",
             {400, :invalid_parameter,
              [not_a_uuid_entry(%{"path" => "project_id"})]}}
          ],
          {verb, id} <- [
            index: nil,
            get: unknown,
            put: unknown,
            delete: unknown
          ],
          {user, {status, code, entries}} <- [
            {c.owner, {403, :forbidden, []}},
            {c.superuser, superuser_answer}
          ],
          do: {pat.(user), verb, project_id, id, status, code, entries}

    for {caller, verb, project_id, id, status, code, entries} <-
          refused ++ refused_lists ++ permitted ++ projects do
      caller
      |> reach(verb, project_id, id)
      |> assert_problem(status, code, entries)
    end

    refute Repo.get(WebhookAuthMethod, unknown)
    assert Repo.reload!(elsewhere).name == "elsewhere"
    assert is_nil(Repo.reload!(elsewhere).scheduled_deletion)
  end

  test "an owner of a project scheduled for deletion gets 409 on every route",
       %{conn: conn} do
    user = insert(:user)

    project =
      insert(:project,
        project_users: [%{user: user, role: :owner}],
        scheduled_deletion: now()
      )

    auth_method = insert(:webhook_auth_method, project: project)
    conn = with_pat(conn, user)

    for verb <- [:index, :get, :put, :delete] do
      id = if verb != :index, do: auth_method.id

      conn
      |> reach(verb, project.id, id)
      |> assert_problem(409, :scheduled_for_deletion, [])
    end
  end
end
