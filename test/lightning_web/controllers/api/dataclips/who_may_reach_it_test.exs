defmodule LightningWeb.API.Dataclips.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Invocation.Dataclip

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    [editor, viewer, short_of_mfa, stranger] = insert_list(4, :user)

    project =
      insert(:project,
        project_users: [
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    mfa_project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: short_of_mfa, role: :owner}]
      )

    %{
      own: insert(:dataclip, project: project, name: "before"),
      mfa_own: insert(:dataclip, project: mfa_project, name: "before"),
      elsewhere: insert(:dataclip, name: "before"),
      editor: assign_bearer(conn, editor),
      viewer: assign_bearer(conn, viewer),
      short_of_mfa: assign_bearer(conn, short_of_mfa),
      stranger: assign_bearer(conn, stranger),
      stranger_session: session_conn(build_conn(), insert(:user)),
      superuser: assign_bearer(conn, insert(:user, role: :superuser))
    }
  end

  describe "who may reach it" do
    test "a caller without permission, or naming an id no person may learn about, gets the same 403 on either route, and nothing is renamed",
         context do
      %{own: own, mfa_own: mfa_own, elsewhere: elsewhere} = context
      unknown = Ecto.UUID.generate()

      every_id = fn record -> [record.id, unknown, "not-a-uuid"] end

      rows =
        for(
          caller <- [:stranger, :stranger_session, :superuser],
          verb <- [:get, :patch],
          id <- every_id.(own),
          do: {caller, verb, id}
        ) ++
          for(
            verb <- [:get, :patch],
            id <- every_id.(mfa_own),
            do: {:short_of_mfa, verb, id}
          ) ++
          for(id <- every_id.(own), do: {:viewer, :patch, id}) ++
          for(
            caller <- [:viewer, :editor],
            verb <- [:get, :patch],
            id <- [unknown, "not-a-uuid", elsewhere.id],
            do: {caller, verb, id}
          )

      for {caller, verb, id} <- rows do
        context
        |> Map.fetch!(caller)
        |> dispatch(@endpoint, verb, "/api/dataclips/#{id}", %{name: "after"})
        |> assert_problem(403, :forbidden, [])
      end

      for dataclip <- [own, mfa_own, elsewhere],
          do: assert(%Dataclip{name: "before"} = Repo.reload(dataclip))
    end

    test "a project scheduled for deletion answers 409 to a member who may otherwise reach the dataclip, and 403 to a stranger",
         %{editor: editor, stranger: stranger, own: own} do
      Repo.update!(
        Ecto.Changeset.change(Repo.preload(own, :project).project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      for verb <- [:get, :patch] do
        editor
        |> dispatch(@endpoint, verb, "/api/dataclips/#{own.id}", %{name: "x"})
        |> assert_problem(409, :scheduled_for_deletion, [])

        stranger
        |> dispatch(@endpoint, verb, "/api/dataclips/#{own.id}", %{name: "x"})
        |> assert_problem(403, :forbidden, [])
      end
    end
  end
end
