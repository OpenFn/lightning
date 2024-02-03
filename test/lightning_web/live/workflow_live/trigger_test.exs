defmodule LightningWeb.WorkflowLive.TriggerTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    workflow = insert(:workflow, project: project)
    trigger = insert(:trigger, type: :webhook, workflow: workflow)

    %{conn: admin_conn, user: admin_user} =
      register_and_log_in_user(%{conn: build_conn()})

    insert(:project_user,
      role: :admin,
      project: project,
      user: admin_user
    )

    [
      workflow: workflow,
      trigger: trigger,
      admin_conn: admin_conn,
      admin_user: admin_user
    ]
  end

  test "authorized users can see link to add authentication method", %{
    conn: conn,
    project: project,
    workflow: workflow,
    trigger: trigger
  } do
    for project_user <-
          Enum.map([:admin, :owner], fn role ->
            insert(:project_user,
              role: role,
              project: project,
              user: build(:user)
            )
          end) do
      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
        )

      assert view |> element("a#addAuthenticationLink") |> has_element?()
      assert view |> element("#webhooks_auth_method_modal") |> has_element?()
    end

    for project_user <-
          Enum.map([:editor, :viewer], fn role ->
            insert(:project_user,
              role: role,
              project: project,
              user: build(:user)
            )
          end) do
      conn = log_in_user(conn, project_user.user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
        )

      assert view
             |> element("a#addAuthenticationLink.cursor-not-allowed")
             |> has_element?()

      refute view |> element("#webhooks_auth_method_modal") |> has_element?()
    end
  end

  test "user can see existing trigger authentication methods", %{
    conn: conn,
    project: project,
    workflow: workflow,
    trigger: trigger
  } do
    {:ok, _view, html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    auth_method =
      insert(:webhook_auth_method,
        project: project,
        auth_type: :basic,
        triggers: [trigger]
      )

    refute html =~ auth_method.name

    {:ok, _view, html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert html =~ auth_method.name
  end

  test "admin can successfully create a basic authentication method, editor cant",
       %{
         conn: conn,
         admin_conn: admin_conn,
         project: project,
         workflow: workflow,
         trigger: trigger
       } do
    modal_id = "webhooks_auth_method_modal"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    refute view |> element("##{modal_id}") |> has_element?()

    {:ok, view, _html} =
      live(
        admin_conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert view |> element("##{modal_id}") |> has_element?()

    html =
      view
      |> form("#choose_auth_type_form_#{modal_id}",
        webhook_auth_method: %{auth_type: "basic"}
      )
      |> render_submit()

    assert html =~ "Create auth method"

    auth_method_name = "funnyauthmethodname"

    refute render(view) =~ auth_method_name

    view
    |> form("#form_#{modal_id}_new_webhook_auth_method",
      webhook_auth_method: %{
        name: auth_method_name,
        username: "testusername",
        password: "testpassword123"
      }
    )
    |> render_submit()

    flash =
      assert_redirect(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert flash["info"] == "Webhook auth method created successfully"

    {:ok, _view, html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert html =~ auth_method_name
  end

  test "admin can successfully create an API authentication method, user can't",
       %{
         conn: conn,
         admin_conn: admin_conn,
         project: project,
         workflow: workflow,
         trigger: trigger
       } do
    modal_id = "webhooks_auth_method_modal"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    refute view |> element("##{modal_id}") |> has_element?()

    {:ok, view, _html} =
      live(
        admin_conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert view |> element("##{modal_id}") |> has_element?()

    html =
      view
      |> form("#choose_auth_type_form_#{modal_id}",
        webhook_auth_method: %{auth_type: "api"}
      )
      |> render_submit()

    assert html =~ "Create auth method"
    assert html =~ "API Key"
    refute html =~ "password"

    auth_method_name = "funnyapiauthmethodname"

    refute render(view) =~ auth_method_name

    assert view
           |> form("#form_#{modal_id}_new_webhook_auth_method",
             webhook_auth_method: %{
               name: auth_method_name
             }
           )
           |> render_submit()

    flash =
      assert_redirect(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert flash["info"] == "Webhook auth method created successfully"

    {:ok, _view, html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert html =~ auth_method_name
  end

  test "admin can successfully update an authentication method, editor cant", %{
    conn: conn,
    admin_conn: admin_conn,
    project: project,
    workflow: workflow,
    trigger: trigger
  } do
    auth_method =
      insert(:webhook_auth_method,
        project: project,
        auth_type: :basic,
        triggers: [trigger]
      )

    modal_id = "webhooks_auth_method_modal"

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    refute view |> element("##{modal_id}") |> has_element?()

    {:ok, view, _html} =
      live(
        admin_conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert view |> element("##{modal_id}") |> has_element?()

    html =
      view
      |> element("#edit_auth_method_link_#{auth_method.id}")
      |> render_click()

    assert html =~ "Edit webhook auth method"

    new_auth_method_name = "funnyapiauthmethodname"

    assert view
           |> form("#form_#{modal_id}_#{auth_method.id}")
           |> render_submit(%{
             webhook_auth_method: %{
               name: new_auth_method_name,
               username: "newusername",
               password: "newpassword123"
             }
           })

    flash =
      assert_redirect(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert flash["info"] == "Webhook auth method updated successfully"

    updated_auth_method =
      Lightning.Repo.get(Lightning.Workflows.WebhookAuthMethod, auth_method.id)

    refute updated_auth_method.name == auth_method.name
    assert updated_auth_method.name == new_auth_method_name

    # only auth method name is updated
    refute auth_method.username == "username"
    assert auth_method.username == updated_auth_method.username

    refute auth_method.password == "newpassword123"
    assert auth_method.password == updated_auth_method.password
  end

  test "admin can successfully remove an authentication method from a trigger, user can't",
       %{
         conn: conn,
         admin_conn: admin_conn,
         project: project,
         workflow: workflow,
         trigger: trigger
       } do
    auth_method =
      insert(:webhook_auth_method,
        project: project,
        auth_type: :basic,
        triggers: [trigger]
      )

    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    refute view |> element("#webhooks_auth_method_modal") |> has_element?()

    {:ok, view, _html} =
      live(
        admin_conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert view |> element("#webhooks_auth_method_modal") |> has_element?()

    view
    |> element("#select_#{auth_method.id}")
    |> render_click()

    view |> element("#update_trigger_auth_methods_button") |> render_click()

    flash =
      assert_redirect(
        view,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id]}"
      )

    assert flash["info"] == "Trigger webhook auth methods updated successfully"

    updated_trigger =
      Lightning.Repo.preload(trigger, [:webhook_auth_methods], force: true)

    assert updated_trigger.webhook_auth_methods == []
  end
end
