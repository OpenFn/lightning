defmodule LightningWeb.API.WebhookAuthMethods.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.SessionHelpers
  import LightningWeb.API.WebhooksChannelsHelpers

  defp link(project, path),
    do:
      LightningWeb.Endpoint.url() <>
        "/api/projects/#{project.id}/webhook_auth_methods" <> path

  defp resource(project, auth_method, attributes) do
    %{
      "type" => "webhook_auth_methods",
      "id" => auth_method.id,
      "attributes" =>
        Map.merge(
          %{
            "name" => auth_method.name,
            "triggers" => [],
            "inserted_at" => DateTime.to_iso8601(auth_method.inserted_at),
            "updated_at" => DateTime.to_iso8601(auth_method.updated_at)
          },
          attributes
        ),
      "relationships" => %{},
      "links" => %{"self" => link(project, "/#{auth_method.id}")}
    }
  end

  defp basic(auth_method, extra),
    do:
      Map.merge(
        %{
          "auth_type" => "basic",
          "username" => auth_method.username,
          "api_key_last_characters" => nil
        },
        extra
      )

  defp api(auth_method, extra \\ %{}),
    do:
      Map.merge(
        %{
          "auth_type" => "api",
          "username" => nil,
          "api_key_last_characters" => String.slice(auth_method.api_key, -5, 5)
        },
        extra
      )

  describe "listing" do
    test "any member lists the project's methods by name, with their triggers, leaving out those scheduled for deletion, and only an owner or admin sees the username and the key's last characters",
         %{conn: conn} do
      viewer = insert(:user)
      editor = insert(:user)
      admin = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: viewer, role: :viewer},
            %{user: editor, role: :editor},
            %{user: admin, role: :admin}
          ]
        )

      workflow = insert(:simple_workflow, project: project)
      trigger = hd(workflow.triggers)

      zeta =
        insert(:webhook_auth_method,
          project: project,
          name: "zeta",
          triggers: [trigger]
        )

      alpha =
        insert(:webhook_auth_method,
          project: project,
          name: "alpha",
          auth_type: :api,
          api_key: "0123456789abcdef"
        )

      insert(:webhook_auth_method,
        project: project,
        name: "middle",
        scheduled_deletion: now()
      )

      insert(:webhook_auth_method, name: "elsewhere")

      page = "?page=1&page_size=10"
      hidden = %{"username" => nil, "api_key_last_characters" => nil}

      for {authenticate, hints} <- [
            {&session_conn(&1, viewer), hidden},
            {&with_pat(&1, editor), hidden},
            {&with_pat(&1, admin), %{}},
            {&session_conn(&1, admin), %{}}
          ] do
        conn =
          conn
          |> authenticate.()
          |> get(~p"/api/projects/#{project.id}/webhook_auth_methods")

        assert json_response(conn, 200) == %{
                 "data" => [
                   resource(project, alpha, alpha |> api() |> Map.merge(hints)),
                   resource(
                     project,
                     zeta,
                     zeta
                     |> basic(%{
                       "triggers" => [
                         %{"id" => trigger.id, "workflow_id" => workflow.id}
                       ]
                     })
                     |> Map.merge(hints)
                   )
                 ],
                 "links" => %{
                   "self" => link(project, page),
                   "first" => link(project, page),
                   "last" => link(project, page),
                   "next" => nil,
                   "prev" => nil
                 }
               }
      end
    end

    test "pages the list", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      [_first, second, _third] =
        for name <- ~w(a b c),
            do: insert(:webhook_auth_method, project: project, name: name)

      conn =
        conn
        |> with_pat(user)
        |> get(
          ~p"/api/projects/#{project.id}/webhook_auth_methods?page=2&page_size=1"
        )

      body = json_response(conn, 200)

      assert Enum.map(body["data"], & &1["id"]) == [second.id]

      assert body["links"] == %{
               "self" => link(project, "?page=2&page_size=1"),
               "first" => link(project, "?page=1&page_size=1"),
               "last" => link(project, "?page=3&page_size=1"),
               "next" => link(project, "?page=3&page_size=1"),
               "prev" => link(project, "?page=1&page_size=1")
             }
    end
  end

  describe "reading one" do
    test "an owner or an admin on a personal access token reads a method, without its secret",
         %{conn: conn} do
      for role <- [:owner, :admin], auth_type <- [:basic, :api] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])
        workflow = insert(:simple_workflow, project: project)
        trigger = hd(workflow.triggers)

        auth_method =
          insert(:webhook_auth_method,
            project: project,
            auth_type: auth_type,
            api_key: if(auth_type == :api, do: "fedcba9876543210"),
            triggers: [trigger]
          )

        conn =
          conn
          |> with_pat(user)
          |> get(
            ~p"/api/projects/#{project.id}/webhook_auth_methods/#{auth_method.id}"
          )

        triggers = %{
          "triggers" => [%{"id" => trigger.id, "workflow_id" => workflow.id}]
        }

        attributes =
          if auth_type == :api,
            do: api(auth_method, triggers),
            else: basic(auth_method, triggers)

        assert json_response(conn, 200) == %{
                 "data" => resource(project, auth_method, attributes)
               }
      end
    end

    test "a stepped-up session token also gets the password or API key", %{
      conn: conn
    } do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      basic_method =
        insert(:webhook_auth_method, project: project, password: "s3cret-pass")

      api_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :api,
          api_key: "fedcba9876543210"
        )

      conn = session_conn(conn, user, stepped_up: true)

      for {auth_method, attributes} <- [
            {basic_method, basic(basic_method, %{"password" => "s3cret-pass"})},
            {api_method, api(api_method, %{"api_key" => "fedcba9876543210"})}
          ] do
        read =
          get(
            conn,
            ~p"/api/projects/#{project.id}/webhook_auth_methods/#{auth_method.id}"
          )

        assert json_response(read, 200) == %{
                 "data" => resource(project, auth_method, attributes)
               }
      end
    end

    test "a session token that isn't stepped up gets no secret", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          auth_type: :api,
          api_key: "fedcba9876543210"
        )

      conn =
        conn
        |> session_conn(user)
        |> get(
          ~p"/api/projects/#{project.id}/webhook_auth_methods/#{auth_method.id}"
        )

      assert json_response(conn, 200) == %{
               "data" => resource(project, auth_method, api(auth_method))
             }
    end
  end
end
