defmodule LightningWeb.SandboxLive.FormComponentTest do
  use LightningWeb.ConnCase, async: true

  use Mimic
  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup_all do
    Mimic.copy(Lightning.Projects)
    Mimic.copy(Lightning.Projects.Sandboxes)
    Mimic.copy(LightningWeb.Live.Helpers.ProjectTheme)
    :ok
  end

  setup :register_and_log_in_user

  describe "new modal" do
    setup %{conn: conn, user: user} do
      parent = insert(:project, project_users: [%{user: user, role: :owner}])

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

    test "creating sandbox with duplicate name shows validation error", %{
      conn: conn,
      parent: parent,
      user: user
    } do
      insert(:sandbox,
        parent: parent,
        name: "test-sandbox",
        project_users: [%{user_id: user.id, role: :owner}]
      )

      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      Mimic.allow(Lightning.Projects, self(), view.pid)

      # Try to create a new sandbox with a name that becomes "test-sandbox"
      view
      |> element("#sandbox-form-new")
      |> render_change(%{
        "project" => %{"raw_name" => "Test Sandbox", "color" => "#abcdef"}
      })

      html = render(view)

      # Verify validation error appears
      assert html =~ "Sandbox name already exists"
    end

    test "creating sandbox with blank name disables submit and shows error",
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
      assert html =~ "can&#39;t be blank"
    end

    test "creating sandbox fails when limiter returns error", %{
      conn: conn,
      parent: %{id: parent_id} = parent,
      test: test
    } do
      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      error_message = "error-#{test}"

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn
          %{type: :new_sandbox, amount: 1}, %{project_id: ^parent_id} ->
            {:error, :exceeded_limit, %{text: error_message}}

          _action, _context ->
            :ok
        end
      )

      view
      |> element("#sandbox-form-new")
      |> render_submit(%{
        "project" => %{"raw_name" => "sb-1", "color" => "#abcdef"}
      })

      flash = assert_redirected(view, ~p"/projects/#{parent.id}/sandboxes")

      assert flash["error"] == error_message
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

      Mimic.stub(
        Lightning.Projects,
        :update_sandbox,
        fn %Lightning.Projects.Project{} = current_sb, user_arg, attrs ->
          assert user_arg.id == user.id

          name = attrs[:name] || attrs["name"]
          env = attrs[:env] || attrs["env"] || current_sb.env
          color = attrs[:color] || attrs["color"]

          if name in [nil, ""] do
            {:error,
             current_sb
             |> Ecto.Changeset.change()
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

    test "updating sandbox with blank name shows error", %{
      conn: conn,
      parent: parent,
      sb: sb
    } do
      {:ok, view, _} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb.id}/edit")

      Mimic.allow(Lightning.Projects, self(), view.pid)

      view
      |> element("#sandbox-form-#{sb.id}")
      |> render_submit(%{"project" => %{"raw_name" => ""}})

      html = render(view)
      assert html =~ "can&#39;t be blank"
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

    test "editing sandbox with duplicate name shows validation error", %{
      conn: conn,
      parent: parent,
      sb: sb,
      user: user
    } do
      insert(:sandbox,
        parent: parent,
        name: "existing-name",
        project_users: [%{user_id: user.id, role: :owner}]
      )

      {:ok, view, _} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb.id}/edit")

      Mimic.allow(Lightning.Projects, self(), view.pid)

      # Try to rename to an existing sandbox name
      view
      |> element("#sandbox-form-#{sb.id}")
      |> render_change(%{"project" => %{"raw_name" => "Existing Name"}})

      html = render(view)

      # Verify validation error appears
      assert html =~ "Sandbox name already exists"
    end

    test "editing sandbox keeping same name does not show validation error", %{
      conn: conn,
      parent: parent,
      sb: sb
    } do
      {:ok, view, _} =
        live(conn, ~p"/projects/#{parent.id}/sandboxes/#{sb.id}/edit")

      Mimic.allow(Lightning.Projects, self(), view.pid)

      # Keep the same name
      view
      |> element("#sandbox-form-#{sb.id}")
      |> render_change(%{"project" => %{"raw_name" => sb.name}})

      html = render(view)

      # Should NOT show validation error
      refute html =~ "Sandbox name already exists"
    end
  end

  describe "theme preview edge cases" do
    setup %{user: user} do
      parent = insert(:project, project_users: [%{user: user, role: :owner}])

      Mimic.stub(
        LightningWeb.Live.Helpers.ProjectTheme,
        :inline_primary_scale,
        fn _project ->
          nil
        end
      )

      {:ok, parent: parent}
    end

    test "generate_theme_preview returns nil when inline_primary_scale returns nil",
         %{
           conn: conn,
           parent: parent
         } do
      Mimic.allow(
        LightningWeb.Live.Helpers.ProjectTheme,
        self(),
        spawn(fn -> :ok end)
      )

      {:ok, view, _} = live(conn, ~p"/projects/#{parent.id}/sandboxes/new")

      view
      |> element("#sandbox-form-new")
      |> render_change(%{"project" => %{"color" => "#ff0000"}})

      html = render(view)

      assert html =~ "Create a new sandbox"

      assert html =~ ~s(#ff0000)

      assert html =~ ~s(name="project[color]")
      assert html =~ ~s(Selected: #ff0000)

      view
      |> element("#sandbox-form-new")
      |> render_change(%{"project" => %{"color" => "#00ff00"}})

      updated_html = render(view)
      assert updated_html =~ ~s(#00ff00)
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
