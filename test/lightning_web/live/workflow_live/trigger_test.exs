defmodule LightningWeb.WorkflowLive.TriggerTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Name
  alias Lightning.Repo
  alias Lightning.Workflows
  alias Lightning.Workflows.WebhookAuthMethod

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    workflow = insert(:workflow, project: project)
    trigger = insert(:trigger, type: :webhook, workflow: workflow)

    {:ok, snapshot} = Workflows.Snapshot.create(workflow)

    [
      workflow: workflow,
      snapshot: snapshot,
      trigger: trigger
    ]
  end

  test "owner/admin can see link to add auth method, editor/viewer can't", %{
    project: project,
    workflow: workflow,
    trigger: trigger
  } do
    for conn <- build_project_user_conns(project, [:owner, :admin]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      assert view |> element("a#addAuthenticationLink") |> has_element?()
      assert view |> element("#webhooks_auth_method_modal") |> has_element?()
    end

    for conn <- build_project_user_conns(project, [:editor, :viewer]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      assert view
             |> element("a#addAuthenticationLink.cursor-not-allowed")
             |> has_element?()

      refute view |> element("#webhooks_auth_method_modal") |> has_element?()
    end
  end

  test "all users can see existing trigger authentication methods", %{
    project: project,
    workflow: workflow,
    trigger: trigger
  } do
    for conn <-
          build_project_user_conns(project, [:owner, :admin, :editor, :viewer]) do
      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      assert html =~ auth_method.name
    end
  end

  test "owner/admin can successfully create a basic authentication method, editor/viewer can't",
       %{
         project: project,
         workflow: workflow,
         trigger: trigger
       } do
    modal_id = "webhooks_auth_method_modal"

    for conn <- build_project_user_conns(project, [:editor, :viewer]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      refute view |> element("##{modal_id}") |> has_element?()
    end

    for conn <- build_project_user_conns(project, [:owner, :admin]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      assert view |> element("##{modal_id}") |> has_element?()

      html =
        view
        |> form("#choose_auth_type_form_#{modal_id}",
          webhook_auth_method: %{auth_type: "basic"}
        )
        |> render_submit()

      assert html =~ "Create auth method"

      auth_method_name = Name.generate()

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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      assert html =~ auth_method_name

      assert %Postgrex.Result{num_rows: 1} =
               Ecto.Adapters.SQL.query!(
                 Repo,
                 "delete from trigger_webhook_auth_methods"
               )

      Repo.get_by(WebhookAuthMethod, name: auth_method_name)
      |> Repo.delete()
    end
  end

  test "admin can successfully create an API authentication method, editor/viewer can't",
       %{
         project: project,
         workflow: workflow,
         trigger: trigger
       } do
    modal_id = "webhooks_auth_method_modal"

    for conn <- build_project_user_conns(project, [:editor, :viewer]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      refute view |> element("##{modal_id}") |> has_element?()
    end

    for conn <- build_project_user_conns(project, [:owner, :admin]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
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

      auth_method_name = Name.generate()

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
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      assert html =~ auth_method_name

      assert %Postgrex.Result{num_rows: 1} =
               Ecto.Adapters.SQL.query!(
                 Repo,
                 "delete from trigger_webhook_auth_methods"
               )

      Repo.get_by(WebhookAuthMethod, name: auth_method_name)
      |> Repo.delete()
    end
  end

  test "admin can successfully update an authentication method, editor cant", %{
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

    for conn <- build_project_user_conns(project, [:editor, :viewer]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      refute view |> element("##{modal_id}") |> has_element?()
    end

    for conn <- build_project_user_conns(project, [:owner, :admin]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      assert view |> element("##{modal_id}") |> has_element?()

      html =
        view
        |> element("#edit_auth_method_link_#{auth_method.id}")
        |> render_click()

      assert html =~ "Rename webhook auth method"

      new_auth_method_name = Name.generate()

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

      updated_auth_method = Repo.get(WebhookAuthMethod, auth_method.id)

      refute updated_auth_method.name == auth_method.name
      assert updated_auth_method.name == new_auth_method_name

      # only auth method name is updated
      refute auth_method.username == "username"
      assert auth_method.username == updated_auth_method.username

      refute auth_method.password == "newpassword123"
      assert auth_method.password == updated_auth_method.password
    end
  end

  test "owner/admin can remove an auth method from a trigger, editor/viewer can't",
       %{
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

    for conn <- build_project_user_conns(project, [:editor, :viewer]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      refute view |> element("#webhooks_auth_method_modal") |> has_element?()
    end

    for conn <- build_project_user_conns(project, [:owner, :admin]) do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
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
        Repo.preload(trigger, [:webhook_auth_methods], force: true)

      assert updated_trigger.webhook_auth_methods == []

      # Then we add it back for the next test role! ============================
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: trigger.id, v: workflow.lock_version]}",
          on_error: :raise
        )

      view
      |> element("#select_#{auth_method.id}")
      |> render_click()

      view |> element("#update_trigger_auth_methods_button") |> render_click()
      # ========================================================================
    end
  end

  test "BETA chip appears for Kafka triggers but not for other trigger types", %{
    project: project,
    workflow: workflow,
    conn: conn
  } do
    # Create different types of triggers
    webhook_trigger = insert(:trigger, type: :webhook, workflow: workflow)
    cron_trigger = insert(:trigger, type: :cron, workflow: workflow)
    kafka_trigger = insert(:trigger, type: :kafka, workflow: workflow)

    # Test for webhook trigger
    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: webhook_trigger.id, v: workflow.lock_version]}",
        on_error: :raise
      )

    # Verify BETA chip is not present for webhook trigger
    refute view |> element("#kafka-trigger-title-beta") |> has_element?()

    refute view
           |> element("span[aria-label*='Kafka triggers are currently in beta']")
           |> has_element?()

    # Test for cron trigger
    {:ok, view, _html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: cron_trigger.id, v: workflow.lock_version]}",
        on_error: :raise
      )

    # Verify BETA chip is not present for cron trigger
    refute view |> element("#kafka-trigger-title-beta") |> has_element?()

    refute view
           |> element("span[aria-label*='Kafka triggers are currently in beta']")
           |> has_element?()

    # Test for kafka trigger
    {:ok, view, html} =
      live(
        conn,
        ~p"/projects/#{project.id}/w/#{workflow.id}?#{[s: kafka_trigger.id, v: workflow.lock_version]}",
        on_error: :raise
      )

    # Verify BETA chip is present for kafka trigger
    assert view |> element("#kafka-trigger-title-beta") |> has_element?()

    # Verify tooltip content
    assert html =~ "Kafka triggers are currently in beta"
    assert html =~ "Learn about the sharp edges"

    assert html =~
             "https://docs.openfn.org/documentation/build/triggers#known-sharp-edges-on-the-kafka-trigger-feature"
  end
end
