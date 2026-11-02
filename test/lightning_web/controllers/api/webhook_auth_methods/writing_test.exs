defmodule LightningWeb.API.WebhookAuthMethods.WritingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import Lightning.RaceHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  alias Lightning.Repo
  alias Lightning.Workflows.WebhookAuthMethod
  alias Lightning.Workflows.WebhookAuthMethodAudit

  setup %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :admin}])
    %{conn: with_pat(conn, user), user: user, project: project}
  end

  defp put_method(conn, project, id, body),
    do:
      send_json(
        conn,
        :put,
        "/api/projects/#{project.id}/webhook_auth_methods/#{id}",
        body
      )

  defp audits(id) do
    Repo.all(
      from a in WebhookAuthMethodAudit.base_query(),
        where: a.item_id == ^id,
        order_by: a.inserted_at
    )
  end

  defp self_link(project, id),
    do:
      LightningWeb.Endpoint.url() <>
        "/api/projects/#{project.id}/webhook_auth_methods/#{id}"

  describe "creating" do
    test "creates a basic method under the path's id, without sending its password back",
         %{conn: conn, user: user, project: project} do
      id = Ecto.UUID.generate()

      conn =
        put_method(conn, project, id, %{
          "id" => id,
          "name" => "partner",
          "auth_type" => "basic",
          "username" => "partner-user",
          "password" => "long-enough"
        })

      created = Repo.get!(WebhookAuthMethod, id)

      assert json_response(conn, 201) == %{
               "data" => %{
                 "type" => "webhook_auth_methods",
                 "id" => id,
                 "attributes" => %{
                   "name" => "partner",
                   "auth_type" => "basic",
                   "username" => "partner-user",
                   "api_key_last_characters" => nil,
                   "triggers" => [],
                   "inserted_at" => DateTime.to_iso8601(created.inserted_at),
                   "updated_at" => DateTime.to_iso8601(created.updated_at)
                 },
                 "relationships" => %{},
                 "links" => %{"self" => self_link(project, id)}
               }
             }

      assert created.project_id == project.id
      assert created.password == "long-enough"
      assert [%{event: "created", actor_id: actor_id}] = audits(id)
      assert actor_id == user.id
    end

    test "a session token creates an api method, and the 201 carries the key Lightning made",
         %{project: project} do
      owner = insert(:user)
      insert(:project_user, project: project, user: owner, role: :owner)
      id = Ecto.UUID.generate()

      conn =
        build_conn()
        |> session_conn(owner)
        |> put_method(project, id, %{"name" => "partner", "auth_type" => "api"})

      %WebhookAuthMethod{api_key: api_key} =
        created = Repo.get!(WebhookAuthMethod, id)

      assert byte_size(api_key) == 64

      assert json_response(conn, 201)["data"]["attributes"] == %{
               "name" => "partner",
               "auth_type" => "api",
               "username" => nil,
               "api_key" => api_key,
               "api_key_last_characters" => String.slice(api_key, -5, 5),
               "triggers" => [],
               "inserted_at" => DateTime.to_iso8601(created.inserted_at),
               "updated_at" => DateTime.to_iso8601(created.updated_at)
             }
    end

    test "refuses a body it cannot take with one 422, each error at its key", %{
      conn: conn,
      project: project
    } do
      unknown = &entry("#/" <> &1, "unknown_key", "is not accepted")
      blank = &entry("#/" <> &1, "required", "can't be blank")

      for {body, entries} <- [
            {%{}, [blank.("name"), blank.("auth_type")]},
            {%{"name" => "x", "auth_type" => "oauth"},
             [entry("#/auth_type", "not_allowed", "is invalid")]},
            {%{"name" => "x", "auth_type" => "basic"},
             [blank.("username"), blank.("password")]},
            {%{
               "name" => "x",
               "auth_type" => "basic",
               "username" => "u",
               "password" => "short"
             },
             [
               entry(
                 "#/password",
                 "too_short",
                 "should be at least 8 character(s)"
               )
             ]},
            {%{
               "name" => "x",
               "auth_type" => "api",
               "api_key" => "chosen",
               "project_id" => insert(:project).id,
               "scheduled_deletion" => "2020-01-01T00:00:00Z"
             },
             [
               unknown.("api_key"),
               unknown.("project_id"),
               unknown.("scheduled_deletion")
             ]},
            {%{
               "name" => "x",
               "auth_type" => "api",
               "id" => Ecto.UUID.generate()
             }, [entry("#/id", "mismatch", "does not match the id in the path")]}
          ] do
        id = Ecto.UUID.generate()

        conn
        |> put_method(project, id, body)
        |> assert_problem(422, :invalid, entries)

        refute Repo.get(WebhookAuthMethod, id)
      end
    end

    test "answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      project: project
    } do
      conn
      |> put_method(project, Ecto.UUID.generate(), ["partner"])
      |> assert_problem(400, :malformed, [])
    end

    test "answers 422 with a taken entry for a name another method in the project has, creating or renaming",
         %{conn: conn, project: project} do
      insert(:webhook_auth_method, project: project, name: "partner")
      other = insert(:webhook_auth_method, project: project, name: "other")
      id = Ecto.UUID.generate()
      taken = [entry("#/name", "taken", "must be unique within the project")]

      conn
      |> put_method(project, id, %{"name" => "partner", "auth_type" => "api"})
      |> assert_problem(422, :invalid, taken)

      conn
      |> put_method(project, other.id, %{"name" => "partner"})
      |> assert_problem(422, :invalid, taken)

      refute Repo.get(WebhookAuthMethod, id)
      assert Repo.reload!(other).name == "other"
    end
  end

  describe "replacing" do
    test "renames the method, recording the actor", %{
      conn: conn,
      user: user,
      project: project
    } do
      auth_method = insert(:webhook_auth_method, project: project, name: "old")

      conn =
        put_method(conn, project, auth_method.id, %{
          "name" => "new",
          "auth_type" => "basic",
          "username" => auth_method.username,
          "password" => auth_method.password
        })

      assert json_response(conn, 200)["data"]["attributes"]["name"] == "new"
      assert Repo.reload!(auth_method).name == "new"

      assert [%{event: "updated", actor_id: actor_id} = audit] =
               audits(auth_method.id)

      assert actor_id == user.id
      assert audit.changes.after == %{"name" => "new"}
    end

    test "re-sending what is stored answers 200 and records nothing", %{
      conn: conn,
      project: project
    } do
      auth_method = insert(:webhook_auth_method, project: project, name: "same")

      conn = put_method(conn, project, auth_method.id, %{"name" => "same"})

      assert json_response(conn, 200)["data"]["id"] == auth_method.id
      assert audits(auth_method.id) == []
    end

    test "refuses a type, username or password other than the stored one with not_allowed",
         %{conn: conn, project: project} do
      basic = insert(:webhook_auth_method, project: project, name: "basic")

      api =
        insert(:webhook_auth_method,
          project: project,
          name: "api",
          auth_type: :api,
          api_key: "0123456789abcdef"
        )

      unchangeable = &entry("#/" <> &1, "not_allowed", "can't be changed")

      for {auth_method, body, entries} <- [
            {basic,
             %{
               "name" => "basic",
               "auth_type" => "api",
               "username" => "someone-else",
               "password" => "another-password"
             },
             [
               unchangeable.("auth_type"),
               unchangeable.("username"),
               unchangeable.("password")
             ]},
            {api, %{"name" => "api", "username" => "u", "password" => "p"},
             [unchangeable.("username"), unchangeable.("password")]}
          ] do
        conn
        |> put_method(project, auth_method.id, body)
        |> assert_problem(422, :invalid, entries)

        assert Repo.reload!(auth_method) |> Map.take([:auth_type, :username]) ==
                 Map.take(auth_method, [:auth_type, :username])

        assert audits(auth_method.id) == []
      end
    end

    test "answers 409 scheduled_for_deletion for a method scheduled for deletion, reading, replacing or deleting it",
         %{conn: conn, project: project} do
      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "going",
          scheduled_deletion: now()
        )

      path =
        ~p"/api/projects/#{project.id}/webhook_auth_methods/#{auth_method.id}"

      for conn <- [
            get(conn, path),
            put_method(conn, project, auth_method.id, %{"name" => "renamed"}),
            delete(conn, path)
          ] do
        assert_problem(conn, 409, :scheduled_for_deletion, [])
      end

      assert Repo.reload!(auth_method).name == "going"
      assert audits(auth_method.id) == []
    end
  end

  describe "deleting" do
    test "a session token schedules the method for deletion, detaching it from its triggers and channels",
         %{project: project} do
      owner = insert(:user)
      insert(:project_user, project: project, user: owner, role: :owner)
      trigger = hd(insert(:simple_workflow, project: project).triggers)

      auth_method =
        insert(:webhook_auth_method, project: project, triggers: [trigger])

      channel = insert(:channel, project: project)

      insert(:channel_auth_method,
        channel: channel,
        webhook_auth_method: auth_method
      )

      conn =
        build_conn()
        |> session_conn(owner)
        |> delete(
          ~p"/api/projects/#{project.id}/webhook_auth_methods/#{auth_method.id}"
        )

      assert response(conn, 204) == ""

      scheduled =
        WebhookAuthMethod
        |> Repo.get!(auth_method.id)
        |> Repo.preload([:triggers, :channels])

      assert scheduled.scheduled_deletion
      assert scheduled.triggers == [] and scheduled.channels == []

      assert "deleted" in Enum.map(audits(auth_method.id), & &1.event)
    end
  end

  describe "stale writes" do
    test "a method another request deletes mid-rename answers 409 concurrent_edit",
         %{conn: conn, project: project} do
      auth_method = insert(:webhook_auth_method, project: project, name: "old")

      after_first_query("webhook_auth_methods", auth_method.id, fn id ->
        Repo.query!("DELETE FROM webhook_auth_methods WHERE id = $1", [id])
      end)

      conn
      |> put_method(project, auth_method.id, %{"name" => "new"})
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(auth_method)
    end

    test "a method another request deletes mid-delete answers 409 concurrent_edit",
         %{conn: conn, project: project} do
      auth_method = insert(:webhook_auth_method, project: project)

      after_first_query("webhook_auth_methods", auth_method.id, fn id ->
        Repo.query!("DELETE FROM webhook_auth_methods WHERE id = $1", [id])
      end)

      conn
      |> delete(
        ~p"/api/projects/#{project.id}/webhook_auth_methods/#{auth_method.id}"
      )
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(auth_method)
      assert audits(auth_method.id) == []
    end
  end
end
