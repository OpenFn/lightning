defmodule LightningWeb.SandboxLive.FormComponentTest do
  use LightningWeb.ConnCase, async: true

  use Mimic
  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup_all do
    Mimic.copy(Lightning.Projects)
    Mimic.copy(Lightning.Projects.Sandboxes)
    :ok
  end

  setup :register_and_log_in_user

  describe "new modal" do
    setup %{conn: conn, user: user} do
      parent = insert(:project, project_users: [%{user: user, role: :owner}])

      # Updated to match the new function signature: provision_sandbox(parent, user, attrs)
      Mimic.stub(Lightning.Projects, :provision_sandbox, fn parent_arg,
                                                            user_arg,
                                                            attrs ->
        assert parent_arg.id == parent.id
        assert user_arg.id == user.id

        name = attrs[:name] || attrs["name"]
        env = attrs[:env] || attrs["env"]
        color = attrs[:color] || attrs["color"]

        if name in [nil, ""] do
          changeset =
            Lightning.Projects.Project.changeset(
              %Lightning.Projects.Project{},
              %{}
            )
            |> Map.put(:action, :insert)
            |> Ecto.Changeset.add_error(:name, "can't be blank")

          {:error, changeset}
        else
          Lightning.Repo.insert(%Lightning.Projects.Project{
            id: Ecto.UUID.generate(),
            parent_id: parent_arg.id,
            name: name,
            env: env,
            color: color
          })
        end
      end)

      {:ok, conn: conn, user: user, parent: parent}
    end

    test "creating sandbox succeeds", %{conn: conn, parent: parent} do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#sandbox-form-new")
      |> render_change(%{
        "project" => %{"raw_name" => "sb-1", "color" => "#abcdef"}
      })

      view
      |> element("#sandbox-form-new")
      |> render_submit(%{
        "project" => %{"raw_name" => "sb-1", "color" => "#abcdef"}
      })
      |> follow_redirect(conn)

      sandbox =
        Lightning.Repo.get_by(Lightning.Projects.Project, parent_id: parent.id)

      flash =
        assert_redirected(view, ~p"/projects/#{sandbox.id}/w")

      assert flash["info"] == "Sandbox created"
    end

    test "creating sandbox with blank name disables submit and keeps placeholder",
         %{
           conn: conn,
           parent: parent
         } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")
      Mimic.allow(Lightning.Projects, self(), view.pid)

      render_submit(
        element(view, "#sandbox-form-new"),
        %{"project" => %{"raw_name" => ""}}
      )

      html = render(view)
      assert html =~ ~s(<button disabled="disabled" type="submit")
      assert html =~ "my-sandbox"
    end
  end

  describe "new modal (cancel)" do
    setup %{conn: conn, user: user} do
      parent = insert(:project, project_users: [%{user: user, role: :owner}])
      {:ok, conn: conn, parent: parent}
    end

    test "clicking Cancel triggers close_modal and navigates back", %{
      conn: conn,
      parent: parent
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      res =
        view
        |> element("button[phx-click='close_modal']", "Cancel")
        |> render_click()

      html =
        assert_redirect_or_patch(
          res,
          view,
          conn,
          ~p"/projects/#{parent.id}/sandboxes"
        )

      assert html =~ "Sandboxes"
    end
  end

  describe "edit modal" do
    setup %{conn: conn, user: user} do
      parent = insert(:project, project_users: [%{user: user, role: :owner}])
      sb = insert(:sandbox, parent: parent, name: "sb-1")

      # Updated to match the new function signature: update_sandbox(sandbox, user, attrs)
      Mimic.stub(
        Lightning.Projects,
        :update_sandbox,
        fn %Lightning.Projects.Project{} = current_sb, user_arg, attrs ->
          assert user_arg.id == user.id

          name = attrs[:name] || attrs["name"]
          env = attrs[:env] || attrs["env"]
          color = attrs[:color] || attrs["color"]

          if name in [nil, ""] do
            {:error,
             %Ecto.Changeset{}
             |> Ecto.Changeset.change(current_sb)
             |> Map.put(:action, :update)
             |> Ecto.Changeset.add_error(:name, "can't be blank")}
          else
            {:ok,
             %Lightning.Projects.Project{
               current_sb
               | name: name,
                 env: env,
                 color: color
             }}
          end
        end
      )

      {:ok, conn: conn, user: user, parent: parent, sb: sb}
    end

    test "updating sandbox succeeds", %{conn: conn, parent: parent, sb: sb} do
      {:ok, view, _} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb.id}/edit")

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#sandbox-form-#{sb.id}")
      |> render_change(%{"project" => %{"raw_name" => "sb-2"}})

      res =
        view
        |> element("#sandbox-form-#{sb.id}")
        |> render_submit(%{"project" => %{"raw_name" => "sb-2"}})

      html =
        assert_redirect_or_patch(
          res,
          view,
          conn,
          ~p"/projects/#{parent.id}/sandboxes"
        )

      assert html =~ "Sandbox updated"
    end

    test "color input displays existing sandbox color", %{
      conn: conn,
      parent: parent
    } do
      sb = insert(:sandbox, parent: parent, name: "sb-colored", color: "#ff0000")

      {:ok, view, _} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb.id}/edit")

      html = render(view)
      assert html =~ "background-color: #ff0000"
      assert html =~ "#ff0000"
      assert html =~ "rounded-md"
    end
  end

  defp assert_redirect_or_patch(res_or_html, view, conn, to) do
    case res_or_html do
      {:error, {:redirect, _}} ->
        {:ok, _v2, html} = follow_redirect(res_or_html, conn, to)
        html

      {:error, {:live_redirect, _}} ->
        {:ok, _v2, html} = follow_redirect(res_or_html, conn, to)
        html

      _html_when_no_redirect ->
        assert_patch(view, to)
        render(view)
    end
  end
end
