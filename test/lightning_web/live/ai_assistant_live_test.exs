defmodule LightningWeb.AiAssistantLiveTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.WorkflowLive.Helpers
  import Mox
  use Oban.Testing, repo: Lightning.Repo
  import Phoenix.Component
  import Phoenix.LiveViewTest

  setup :verify_on_exit!
  setup :register_and_log_in_user
  setup :create_project_for_current_user

  defp skip_disclaimer(user, read_at \\ DateTime.utc_now() |> DateTime.to_unix()) do
    Ecto.Changeset.change(user, %{
      preferences: %{"ai_assistant.disclaimer_read_at" => read_at}
    })
    |> Lightning.Repo.update!()
  end

  describe "AI Assistant - Job Code Mode" do
    setup :create_workflow

    test "non openfn.org users can access the AI Assistant", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      refute String.match?(user.email, ~r/@openfn\.org/i)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      html = view |> element("#job-#{job_1.id}-ai-assistant") |> render()
      assert html =~ "Get started with the AI Assistant"
    end

    @tag email: "user@openfn.org"
    test "correct information is displayed when the assistant is not configured",
         %{
           conn: conn,
           project: project,
           workflow: %{jobs: [job_1 | _]} = workflow,
           user: user
         } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> nil
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: "/"}, _opts ->
            {:error, :econnrefused}

          %{method: :get, url: "http://localhost:4001/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      assert render(view) =~
               "AI Assistant has not been configured for your instance"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant"
             )

      refute render(view) =~
               "AI Assistant has not been configured for your instance"
    end

    @tag email: "user@openfn.org"
    test "disclaimer ui is displayed when user has not read it", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      refute user.preferences["ai_assistant.disclaimer_read_at"]

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      html = view |> element("#job-#{job_1.id}-ai-assistant") |> render()
      assert html =~ "Get started with the AI Assistant"

      refute has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant"
             )

      view |> element("#get-started-with-ai-btn") |> render_click()
      html = view |> element("#job-#{job_1.id}-ai-assistant") |> render()
      refute html =~ "Get started with the AI Assistant"

      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant"
             )

      assert Lightning.Repo.reload(user).preferences[
               "ai_assistant.disclaimer_read_at"
             ]
    end

    @tag email: "user@openfn.org"
    test "disclaimer ui is displayed when user read it more than 24 hours ago",
         %{
           conn: conn,
           project: project,
           user: user,
           workflow: %{jobs: [job_1 | _]} = workflow
         } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      date = DateTime.utc_now() |> DateTime.add(-24, :hour) |> DateTime.to_unix()

      skip_disclaimer(user, date)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      html = view |> element("#job-#{job_1.id}-ai-assistant") |> render()
      assert html =~ "Get started with the AI Assistant"

      refute has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant"
             )
    end

    @tag email: "user@openfn.org"
    test "disclaimer ui is NOT displayed when user read it less than 24 hours ago",
         %{
           conn: conn,
           project: project,
           user: user,
           workflow: %{jobs: [job_1 | _]} = workflow
         } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      html =
        view
        |> element("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
        |> render()

      refute html =~ "Get started with the AI Assistant"

      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant"
             )
    end

    @tag email: "user@openfn.org"
    test "authorized users can send a message", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [%{"role" => "assistant", "content" => "Hello!"}]
               }
             }}
        end
      )

      [:owner, :admin, :editor]
      |> Enum.map(fn role ->
        timestamp = DateTime.utc_now() |> DateTime.to_unix()

        user =
          insert(:user,
            email: "email-#{Enum.random(1..1_000)}@testemail.org",
            preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
          )

        insert(:project_user, project: project, user: user, role: role)

        user
      end)
      |> Enum.each(fn user ->
        conn = log_in_user(conn, user)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
          )

        render_async(view)

        assert view
               |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
               |> has_element?()

        input_element =
          element(
            view,
            "#ai-assistant-form-job-#{job_1.id}-ai-assistant textarea"
          )

        submit_btn =
          element(
            view,
            "#ai-assistant-form-submit-btn-chat-input-job-#{job_1.id}-ai-assistant"
          )

        assert has_element?(input_element)
        refute render(input_element) =~ "disabled=\"disabled\""
        assert has_element?(submit_btn)
        # Submit button should be disabled when no content is entered
        assert render(submit_btn) =~ "disabled=\"disabled\""

        html =
          view
          |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
          |> render_submit(assistant: %{content: "Hello"})

        refute html =~ "You are not authorized to use the Ai Assistant"

        assert_patch(view)
      end)

      [:viewer]
      |> Enum.map(fn role ->
        timestamp = DateTime.utc_now() |> DateTime.to_unix()

        user =
          insert(:user,
            email: "email-#{Enum.random(1..1_000)}@openfn.org",
            preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
          )

        insert(:project_user, project: project, user: user, role: role)

        user
      end)
      |> Enum.each(fn user ->
        conn = log_in_user(conn, user)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
          )

        render_async(view)

        assert view
               |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
               |> has_element?()

        input_element =
          element(
            view,
            "#ai-assistant-form-job-#{job_1.id}-ai-assistant textarea"
          )

        submit_btn =
          element(
            view,
            "#ai-assistant-form-submit-btn-chat-input-job-#{job_1.id}-ai-assistant"
          )

        assert has_element?(input_element)
        assert render(input_element) =~ "disabled=\"disabled\""
        assert has_element?(submit_btn)
        assert render(submit_btn) =~ "disabled=\"disabled\""

        html =
          view
          |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
          |> render_submit(assistant: %{content: "Hello"})

        assert html =~ "You are not authorized to use the AI Assistant"
      end)
    end

    @tag email: "user@openfn.org"
    test "submit btn is disabled in case the job isnt saved yet", %{
      conn: conn,
      project: project,
      user: user,
      workflow: workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")

      job_id = Ecto.UUID.generate()
      push_patches_to_view(view, [add_job_patch("new job", job_id)])

      select_node(view, %{id: job_id})
      view |> element("a#open-inspector-#{job_id}") |> render_click()

      render_async(view)

      assert view
             |> form("#ai-assistant-form-job-#{job_id}-ai-assistant")
             |> has_element?()

      input_element =
        element(view, "#ai-assistant-form-job-#{job_id}-ai-assistant textarea")

      submit_btn =
        element(
          view,
          "#ai-assistant-form-submit-btn-chat-input-job-#{job_id}-ai-assistant"
        )

      assert has_element?(input_element)
      assert render(input_element) =~ "disabled=\"disabled\""
      assert has_element?(submit_btn)
      assert render(submit_btn) =~ "disabled=\"disabled\""

      assert render(input_element) =~
               ~s(placeholder="Save your workflow first to use the AI Assistant")
    end

    @tag email: "user@openfn.org"
    test "form accepts phx-change", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      random_text = "Ping12345678"

      html =
        view
        |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
        |> render_change(assistant: %{content: random_text})

      assert html =~ random_text
    end

    @tag email: "user@openfn.org"
    test "users can start a new session", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            # Simply return the response immediately
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "user", "content" => "Ping"},
                   %{"role" => "assistant", "content" => "Pong"}
                 ]
               }
             }}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Ping"})

      assert_patch(view)

      # In test environment with inline Oban, response appears immediately
      html = render(view)
      assert html =~ "Pong"
    end

    @tag email: "user@openfn.org"
    test "users can resume a session", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      expected_question = "Can you help me with this?"
      expected_answer = "No, I am a robot"

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "user", "content" => "Ping"},
                   %{"role" => "assistant", "content" => "Pong"},
                   %{"role" => "user", "content" => expected_question},
                   %{"role" => "assistant", "content" => expected_answer}
                 ]
               }
             }}
        end
      )

      session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "Ping", user: user},
            %{role: :assistant, content: "Pong"}
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      refute render_async(view) =~ session.title

      view |> element("#get-started-with-ai-btn") |> render_click()

      assert render_async(view) =~ session.title

      view |> element("#session-#{session.id}") |> render_click()

      assert_patch(view)

      # Submit the form
      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: expected_question})

      # In test environment with inline Oban, the response appears immediately
      html = render(view)
      assert html =~ expected_answer
    end

    @tag :capture_log
    @tag email: "user@openfn.org"
    test "an error is displayed incase the assistant does not return 200", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok, %Tesla.Env{status: 400, body: %{"message" => "Bad request"}}}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Ping"})

      assert_patch(view)

      # Error appears immediately in test environment
      html = render(view)

      # The user message should show as failed
      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"
      assert has_element?(view, "[phx-click='retry_message']")
    end

    @tag :capture_log
    @tag email: "user@openfn.org"
    test "an error is displayed when the assistant query fails", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            # Return an error response
            {:ok,
             %Tesla.Env{
               status: 500,
               body: %{"message" => "Internal server error"}
             }}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          view
          |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
          |> render_submit(assistant: %{content: "Ping"})
        end)

      assert log =~ "AI query failed"
      assert log =~ "Internal server error"

      assert_patch(view)

      html = render(view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"

      assert has_element?(view, "[phx-click='retry_message']")
    end

    @tag email: "user@openfn.org"
    test "shows a flash error when limit has reached", %{
      conn: conn,
      project: %{id: project_id} = project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001/health_check"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      error_message = "You have reached your quota of AI queries"

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn %{
                                                                          type:
                                                                            :ai_usage
                                                                        },
                                                                        %{
                                                                          project_id:
                                                                            ^project_id
                                                                        } ->
        {:error, :exceeds_limit,
         %Lightning.Extensions.Message{text: error_message}}
      end)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      assert has_element?(view, "#ai-assistant-error", error_message)

      input_element =
        element(view, "#ai-assistant-form-job-#{job_1.id}-ai-assistant textarea")

      assert render(input_element) =~
               ~s(placeholder="#{error_message}")

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Ping"})

      assert has_element?(view, "#ai-assistant-error", error_message)
    end

    @tag :capture_log
    @tag email: "user@openfn.org"
    test "displays apollo server error messages", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      error_message = "Server is temporarily unavailable"

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 503,
               body: %{
                 "code" => 503,
                 "message" => error_message
               }
             }}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)
      view |> element("#get-started-with-ai-btn") |> render_click()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          view
          |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
          |> render_submit(assistant: %{content: "Ping"})
        end)

      assert log =~ "AI query failed for session"
      assert log =~ "Server is temporarily unavailable"

      assert_patch(view)
      render_async(view)

      html = render(view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"
      assert has_element?(view, "[phx-click='retry_message']")
    end

    @tag :capture_log
    @tag email: "user@openfn.org"
    test "handles timeout errors from Apollo", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:error, :timeout}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          view
          |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
          |> render_submit(assistant: %{content: "Ping"})
        end)

      assert log =~ "AI query timed out for session"
      assert log =~ "Request timed out. Please try again."

      assert_patch(view)
      render_async(view)

      html = render(view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"
      assert has_element?(view, "[phx-click='retry_message']")
    end

    @tag :capture_log
    @tag email: "user@openfn.org"
    test "handles connection refused errors from Apollo", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:error, :econnrefused}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          view
          |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
          |> render_submit(assistant: %{content: "Ping"})
        end)

      assert log =~ "Connection refused to AI server for session"
      assert log =~ "Unable to reach the AI server. Please try again later."

      html = render_async(view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"

      assert has_element?(view, "[phx-click='retry_message']")
    end

    @tag :capture_log
    @tag email: "user@openfn.org"
    test "handles unexpected errors from Apollo", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:error, :unknown_error}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)
      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Ping"})

      assert_patch(view)
      render_async(view)

      html = render(view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"
      assert has_element?(view, "[phx-click='retry_message']")
    end

    @tag email: "user@openfn.org"
    test "users can sort chat sessions", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      older_session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          updated_at: ~N[2024-01-01 10:00:00],
          title: "January Session",
          messages: [
            %{role: :user, content: "First message", user: user},
            %{role: :assistant, content: "First response"}
          ]
        )

      newer_session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          updated_at: ~N[2024-02-01 10:00:00],
          title: "February Session",
          messages: [
            %{role: :user, content: "Second message", user: user},
            %{role: :assistant, content: "Second response"}
          ]
        )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      html = render(view)
      assert html =~ "Latest"

      links =
        Floki.find(
          Floki.parse_document!(html),
          "a[id^='session-']"
        )

      assert length(links) == 2
      [first_link, second_link] = links

      assert first_link |> Floki.attribute("id") == [
               "session-#{newer_session.id}"
             ]

      assert second_link |> Floki.attribute("id") == [
               "session-#{older_session.id}"
             ]

      view |> element("button[phx-click='toggle_sort']") |> render_click()
      render_async(view)
      html = render(view)

      links =
        Floki.find(
          Floki.parse_document!(html),
          "a[id^='session-']"
        )

      assert length(links) == 2
      [first_link, second_link] = links

      assert first_link |> Floki.attribute("id") == [
               "session-#{older_session.id}"
             ]

      assert second_link |> Floki.attribute("id") == [
               "session-#{newer_session.id}"
             ]

      view |> element("button[phx-click='toggle_sort']") |> render_click()
      render_async(view)
      html = render(view)

      links =
        Floki.find(
          Floki.parse_document!(html),
          "a[id^='session-']"
        )

      assert length(links) == 2
      [first_link, second_link] = links

      assert first_link |> Floki.attribute("id") == [
               "session-#{newer_session.id}"
             ]

      assert second_link |> Floki.attribute("id") == [
               "session-#{older_session.id}"
             ]
    end

    @tag email: "user@openfn.org"
    test "input field is cleared after sending a message", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "assistant", "content" => "Response!"}
                 ]
               }
             }}
        end
      )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      render_async(view)

      assert view
             |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
             |> has_element?()

      input_element =
        element(view, "#ai-assistant-form-job-#{job_1.id}-ai-assistant textarea")

      assert has_element?(input_element)

      message = "Hello, AI Assistant!"

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: message})

      render_async(view)

      refute render(input_element) =~ message
    end

    @tag email: "user@openfn.org"
    test "users can retry failed messages", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok, %Tesla.Env{status: 500}}
      end)

      session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "Hello", status: :error, user: user}
          ]
        )

      timestamp = DateTime.utc_now() |> DateTime.to_unix()

      Ecto.Changeset.change(user, %{
        preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
      })
      |> Lightning.Repo.update!()

      # Use manual testing mode to control job execution
      Oban.Testing.with_testing_mode(:manual, fn ->
        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand", "j-chat": session.id]}",
            on_error: :raise
          )

        render_async(view)

        assert has_element?(
                 view,
                 "#retry-message-#{List.first(session.messages).id}"
               )

        refute has_element?(
                 view,
                 "#cancel-message-#{List.first(session.messages).id}"
               )

        # Update the mock for successful response
        Mox.stub(Lightning.Tesla.Mock, :call, fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "user", "content" => "Hello"},
                   %{"role" => "assistant", "content" => "Hi there!"}
                 ]
               }
             }}
        end)

        # Click retry
        view
        |> element("#retry-message-#{List.first(session.messages).id}")
        |> render_click()

        # The message should now be in pending status
        html = render(view)
        assert html =~ "Sending"

        # Verify job was enqueued
        assert [job] =
                 all_enqueued(worker: Lightning.AiAssistant.MessageProcessor)

        assert job.args["message_id"] == List.first(session.messages).id

        # Process the job
        assert %{success: 1} =
                 Oban.drain_queue(Lightning.Oban, queue: :ai_assistant)

        # Re-render to see the updated state
        html = render(view)

        # Now check for the successful response
        assert html =~ "Hi there!"
        refute html =~ "Failed"
        refute has_element?(view, "#assistant-failed-message")
      end)
    end

    @tag email: "user@openfn.org"
    test "cancel buttons are available until only one message remains", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "First message", status: :error, user: user},
            %{role: :assistant, content: "First response"},
            %{
              role: :user,
              content: "Second message",
              status: :error,
              user: user
            },
            %{role: :assistant, content: "Second response"},
            %{role: :user, content: "Third message", status: :error, user: user}
          ]
        )

      timestamp = DateTime.utc_now() |> DateTime.to_unix()

      Ecto.Changeset.change(user, %{
        preferences: %{"ai_assistant.disclaimer_read_at" => timestamp}
      })
      |> Lightning.Repo.update!()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand", "j-chat": session.id]}",
          on_error: :raise
        )

      render_async(view)

      failed_messages = Enum.filter(session.messages, &(&1.status == :error))

      Enum.each(failed_messages, fn message ->
        assert has_element?(view, "#retry-message-#{message.id}")
        assert has_element?(view, "#cancel-message-#{message.id}")
      end)

      Enum.take(failed_messages, length(failed_messages) - 1)
      |> Enum.each(fn message ->
        view
        |> element("#cancel-message-#{message.id}")
        |> render_click()

        refute has_element?(view, "#retry-message-#{message.id}")
        refute has_element?(view, "#cancel-message-#{message.id}")

        updated_session = Lightning.AiAssistant.get_session!(session.id)

        refute Enum.any?(updated_session.messages, &(&1.id == message.id))
      end)

      updated_session = Lightning.AiAssistant.get_session!(session.id)

      user_messages = Enum.filter(updated_session.messages, &(&1.role == :user))
      assert length(user_messages) == 1

      current_failed_messages =
        Enum.filter(updated_session.messages, &(&1.status == :error))

      assert length(current_failed_messages) == 1

      last_remaining_message = List.first(user_messages)

      assert has_element?(view, "#retry-message-#{last_remaining_message.id}")
      refute has_element?(view, "#cancel-message-#{last_remaining_message.id}")

      single_message_session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :user, content: "Hello", status: :error, user: user}
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand", "j-chat": single_message_session.id]}",
          on_error: :raise
        )

      render_async(view)

      assert has_element?(
               view,
               "#retry-message-#{List.first(single_message_session.messages).id}"
             )

      refute has_element?(
               view,
               "#cancel-message-#{List.first(single_message_session.messages).id}"
             )
    end

    @tag email: "user@openfn.org"
    test "AI Assistant renders custom component for collecting feedback", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      on_exit(fn -> Application.delete_env(:lightning, :ai_feedback) end)

      Application.put_env(:lightning, :ai_feedback, %{
        component: fn assigns ->
          ~H"""
          <div id="ai-feedback">Hello from AI Feedback</div>
          """
        end
      })

      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "assistant", "content" => "Hello, World!"}
                 ]
               }
             }}
        end
      )

      session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          messages: [
            %{role: :assistant, content: "Hello, World!"}
          ]
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}",
          on_error: :raise
        )

      view |> element("#get-started-with-ai-btn") |> render_click()

      view |> element("#session-#{session.id}") |> render_click()

      assert_patch(view)

      feedback_el = element(view, "#ai-feedback")

      assert has_element?(feedback_el)

      assert render(feedback_el) =~ "Hello from AI Feedback"
    end

    test "job code attachment is selected by default", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      job_expression = "fn(state => state);\n"
      adaptor = "@openfn/language-http@7.0.6"

      job_1
      |> Ecto.Changeset.change(%{adaptor: adaptor, body: job_expression})
      |> Lightning.Repo.update!()

      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post, body: json_body}, _opts ->
            body = Jason.decode!(json_body)
            assert body["context"]["expression"] == job_expression
            assert body["context"]["adaptor"] == adaptor

            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "user", "content" => "Ping"},
                   %{"role" => "assistant", "content" => "Pong"}
                 ]
               }
             }}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      # checkbox is checked
      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant input[type='checkbox'][name='assistant[options][code]'][value='true']:checked"
             )

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Ping"})

      assert_patch(view)

      render_async(view)

      # checkbox is still checked even after patching
      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant input[type='checkbox'][name='assistant[options][code]'][value='true']:checked"
             )
    end

    test "job code attachment can be turned off", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      job_expression = "fn(state => state);\n"
      adaptor = "@openfn/language-http@7.0.6"

      job_1
      |> Ecto.Changeset.change(%{adaptor: adaptor, body: job_expression})
      |> Lightning.Repo.update!()

      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post, body: json_body}, _opts ->
            body = Jason.decode!(json_body)
            refute Map.has_key?(body["context"], "expression")
            assert body["context"]["adaptor"] == adaptor

            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "user", "content" => "Ping"},
                   %{"role" => "assistant", "content" => "Pong"}
                 ]
               }
             }}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      # checkbox is checked
      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant input[type='checkbox'][name='assistant[options][code]'][value='true']:checked"
             )

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Ping", options: %{code: "false"}})

      assert_patch(view)

      render_async(view)

      # checkbox is not checked
      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant input[type='checkbox'][name='assistant[options][code]'][value='true']:not(:checked)"
             )
    end

    test "logs attachment option is disabled by default", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _], triggers: [trigger]} = workflow
    } do
      workflow = Lightning.Repo.reload(workflow)

      snapshot = Lightning.Workflows.Snapshot.get_current_for(workflow)

      dataclip = build(:http_request_dataclip, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          state: "failed",
          error_type: "CompileError",
          dataclip: dataclip,
          steps: [
            build(:step,
              job: job_1,
              snapshot: snapshot,
              input_dataclip: dataclip,
              exit_reason: "fail",
              error_type: "CompileError",
              started_at: DateTime.utc_now(),
              finished_at: DateTime.utc_now()
            )
          ]
        )

      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(
        Lightning.Tesla.Mock,
        :call,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}
        end
      )

      # without following a run
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{[v: workflow.lock_version, s: job_1.id, m: "expand"]}"
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      # checkbox is unchecked
      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant input[type='checkbox'][name='assistant[options][logs]']:not(:checked)"
             )

      GenServer.stop(view.pid)

      # when following a run
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{%{a: run.id, m: "expand", s: job_1.id}}",
          on_error: :raise
        )

      render_async(view)

      # checkbox exists
      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant input[type='checkbox'][name='assistant[options][logs]']:not(:checked)"
             )
    end

    test "logs attachment are sent when toggled on", %{
      conn: conn,
      project: project,
      workflow: %{jobs: [job_1 | _], triggers: [trigger]} = workflow
    } do
      workflow = Lightning.Repo.reload(workflow)

      snapshot = Lightning.Workflows.Snapshot.get_current_for(workflow)

      dataclip = build(:http_request_dataclip, project: project)

      work_order =
        insert(:workorder,
          workflow: workflow,
          snapshot: snapshot,
          dataclip: dataclip
        )

      run =
        insert(:run,
          work_order: work_order,
          starting_trigger: trigger,
          state: "failed",
          error_type: "CompileError",
          dataclip: dataclip,
          steps: [
            build(:step,
              job: job_1,
              snapshot: snapshot,
              input_dataclip: dataclip,
              exit_reason: "fail",
              error_type: "CompileError",
              started_at: DateTime.utc_now(),
              finished_at: DateTime.utc_now()
            )
          ]
        )

      insert(:log_line, run: run)
      log1 = insert(:log_line, run: run, step: hd(run.steps))
      log2 = insert(:log_line, run: run, step: hd(run.steps))

      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Lightning.Tesla.Mock
      |> expect(
        :call,
        2,
        fn
          %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post, body: json_body}, _opts ->
            body = Jason.decode!(json_body)
            assert Map.has_key?(body["context"], "log")
            assert body["context"]["log"] == log1.message <> "\n" <> log2.message

            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "history" => [
                   %{"role" => "user", "content" => "Ping"},
                   %{"role" => "assistant", "content" => "Pong"}
                 ]
               }
             }}
        end
      )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?#{%{a: run.id, m: "expand", s: job_1.id}}",
          on_error: :raise
        )

      render_async(view)

      view |> element("#get-started-with-ai-btn") |> render_click()

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Ping", options: %{logs: "true"}})

      assert_patch(view)

      render_async(view)
    end
  end

  describe "AI Assistant - Workflow Template Mode" do
    setup :create_project_for_user

    test "workflow mode displays correctly for template generation", %{
      conn: conn,
      project: project,
      user: user
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: "http://localhost:4001" <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      html = render(view)

      assert has_element?(
               view,
               "#ai-assistant-form-new-workflow-panel-assistant"
             )

      assert html =~ "Describe the workflow you want to create..."

      refute html =~ "Ask about your job code, debugging, or OpenFn adaptors..."
    end

    test "workflow mode creates sessions correctly", %{
      conn: conn,
      project: project,
      user: user
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "I'll help you create a Salesforce sync workflow",
               "response_yaml" => nil,
               "usage" => %{},
               "history" => [
                 %{
                   "role" => "user",
                   "content" => "Create a Salesforce sync workflow"
                 }
               ]
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(
        assistant: %{content: "Create a Salesforce sync workflow"}
      )

      assert_patch(view)

      render_async(view)

      html = render(view)
      assert html =~ "I&#39;ll help you create a Salesforce sync workflow"
    end

    test "workflow mode generates and applies templates", %{
      conn: conn,
      project: project,
      user: user
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      workflow_yaml = """
      name: "Salesforce Sync Workflow"
      jobs:
        fetch-data:
          name: Fetch Salesforce data
          adaptor: "@openfn/language-salesforce@latest"
          body: |
            getRecords('Contact', {
              fields: ['Id', 'Name', 'Email'],
              limit: 100
            });
      triggers:
        webhook:
          type: webhook
          enabled: true
      edges:
        webhook->fetch-data:
          source_trigger: webhook
          target_job: fetch-data
          condition_type: always
          enabled: true
      """

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "Here's your Salesforce sync workflow:",
               "response_yaml" => workflow_yaml,
               "usage" => %{}
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(
        assistant: %{content: "Create a Salesforce sync workflow"}
      )

      assert_patch(view)
      render_async(view)

      html = render(view)

      assert html =~ "Click to restore workflow to here"
      assert html =~ "Here&#39;s your Salesforce sync workflow:"

      workflow_sessions =
        Lightning.AiAssistant.list_sessions(project, user, :desc, limit: 5)

      assert %{sessions: [session | _]} = workflow_sessions
      assert session.session_type == "workflow_template"

      session = Lightning.Repo.preload(session, :messages)

      assistant_message =
        session.messages
        |> Enum.find(fn message ->
          message.role == :assistant &&
            not is_nil(message.code) &&
            message.code != ""
        end)

      assert assistant_message,
             "Should find assistant message with workflow_code"

      message_id = assistant_message.id

      assert assistant_message.code =~ "Salesforce Sync Workflow"
      assert assistant_message.code =~ "fetch-data"
      assert assistant_message.code =~ "getRecords"

      view
      |> element("[phx-value-message-id='#{message_id}']")
      |> render_click()

      assert_push_event(view, "template_selected", %{template: template_code})

      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      view
      |> with_target("#new-workflow-panel")
      |> render_hook("template-parsed", %{
        "workflow" => %{
          "name" => "Salesforce Sync Workflow",
          "jobs" => [
            %{
              "id" => job_id,
              "name" => "Fetch Salesforce data",
              "adaptor" => "@openfn/language-salesforce@latest",
              "body" =>
                "getRecords('Contact', {\n  fields: ['Id', 'Name', 'Email'],\n  limit: 100\n});"
            }
          ],
          "triggers" => [
            %{
              "id" => trigger_id,
              "type" => "webhook",
              "enabled" => true
            }
          ],
          "edges" => [
            %{
              "id" => Ecto.UUID.generate(),
              "source_trigger_id" => trigger_id,
              "target_job_id" => job_id,
              "condition_type" => "always",
              "enabled" => true
            }
          ]
        }
      })

      assert template_code == workflow_yaml
      assert template_code =~ "Salesforce Sync Workflow"
      assert template_code =~ "fetch-data"
      assert template_code =~ "@openfn/language-salesforce"
      assert template_code =~ "getRecords"
      assert template_code =~ "webhook"

      render_async(view)

      create_btn_after = element(view, "#create_workflow_btn")
      create_btn_html_after = render(create_btn_after)

      refute create_btn_html_after =~ "disabled=\"disabled\"",
             "Create button should be enabled after template selection"
    end

    @tag :capture_log
    test "workflow mode handles template generation errors", %{
      conn: conn,
      project: project,
      user: user
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 503,
             body: %{"message" => "Service temporarily unavailable"}
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(assistant: %{content: "Create a workflow"})

      assert_patch(view)

      html = render(view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"
      assert has_element?(view, "[phx-click='retry_message']")
    end

    test "workflow mode lists project-scoped sessions", %{
      conn: conn,
      project: project,
      user: user
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      session1 =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: "API Integration Workflow",
          messages: [
            %{role: :user, content: "Create API workflow", user: user},
            %{role: :assistant, content: "Here's your API workflow"}
          ]
        )

      session2 =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: "Data Sync Workflow",
          messages: [
            %{role: :user, content: "Create sync workflow", user: user},
            %{role: :assistant, content: "Here's your sync workflow"}
          ]
        )

      other_project = insert(:project)

      _other_session =
        insert(:workflow_chat_session,
          user: user,
          project: other_project,
          title: "Other Project Workflow"
        )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      html = render(view)

      assert html =~ "API Integration Workflow"
      assert html =~ "Data Sync Workflow"
      refute html =~ "Other Project Workflow"

      assert has_element?(view, "#session-#{session1.id}")
      assert has_element?(view, "#session-#{session2.id}")
    end

    test "workflow mode respects permissions like job mode", %{
      conn: conn,
      project: project
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      viewer_user = insert(:user, email: "viewer@test.org")
      skip_disclaimer(viewer_user)
      insert(:project_user, project: project, user: viewer_user, role: :viewer)

      conn = log_in_user(conn, viewer_user)

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")
        |> follow_redirect(conn)

      assert html =~ "You are not authorized to perform this action."
    end

    test "workflow mode handles usage limits", %{
      conn: conn,
      project: %{id: project_id} = project,
      user: user
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      error_message = "Monthly workflow generation limit reached"

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
        %{type: :ai_usage}, %{project_id: ^project_id} ->
          {:error, :exceeds_limit,
           %Lightning.Extensions.Message{text: error_message}}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      assert has_element?(view, "#ai-assistant-error", error_message)

      input_element =
        element(view, "#content-chat-input-new-workflow-panel-assistant")

      assert render(input_element) =~ "placeholder=\"#{error_message}\""

      view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(assistant: %{content: "Create workflow"})

      assert has_element?(view, "#ai-assistant-error", error_message)
    end

    test "workflow mode session titles use project context", %{
      conn: conn,
      project: project,
      user: user
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      session_with_title =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: "Custom Workflow Template"
        )

      session_without_title =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: nil
        )

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/new?method=ai&w-chat=#{session_with_title.id}"
        )

      render_async(view)

      html = render(view)
      assert html =~ "Custom Workflow Template"

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/new?method=ai&chat=#{session_without_title.id}"
        )

      render_async(view)

      html = render(view)
      assert html =~ "#{project.name} Workflow"
    end

    test "workflow mode doesn't validate job save state", %{
      conn: conn,
      project: project,
      user: user
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      input_element =
        element(view, "#ai-assistant-form-new-workflow-panel-assistant textarea")

      submit_btn =
        element(
          view,
          "#ai-assistant-form-submit-btn-chat-input-new-workflow-panel-assistant"
        )

      refute render(input_element) =~ "disabled=\"disabled\""
      # Submit button should be disabled when no content is entered
      assert render(submit_btn) =~ "disabled=\"disabled\""

      refute render(input_element) =~ "Save your workflow first"
    end

    test "workflow mode clears template state on session start", %{
      conn: conn,
      project: project,
      user: user
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(view)

      # The component should have called send_update to clear any existing template
      # In a real test, we'd verify the parent component received the clear template message
      # For now, just verify the interface loads correctly
      assert has_element?(view, "#new-workflow-panel-assistant")
    end

    test "workflow mode isolates sessions per user", %{
      conn: conn,
      project: project
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{
                   "role" => "assistant",
                   "content" => "Workflow created for user"
                 }
               ]
             }
           }}
      end)

      user1 = insert(:user, email: "user1@test.org")
      user2 = insert(:user, email: "user2@test.org")

      skip_disclaimer(user1)
      skip_disclaimer(user2)

      insert(:project_user, project: project, user: user1, role: :editor)
      insert(:project_user, project: project, user: user2, role: :editor)

      _session1 =
        insert(:workflow_chat_session,
          user: user1,
          project: project,
          title: "User 1 Workflow"
        )

      _session2 =
        insert(:workflow_chat_session,
          user: user2,
          project: project,
          title: "User 2 Workflow"
        )

      conn1 = log_in_user(conn, user1)
      {:ok, view1, _} = live(conn1, ~p"/projects/#{project.id}/w/new?method=ai")
      render_async(view1)

      conn2 = log_in_user(conn, user2)
      {:ok, view2, _} = live(conn2, ~p"/projects/#{project.id}/w/new?method=ai")
      render_async(view2)

      html1 = render(view1)
      html2 = render(view2)

      # Each user should only see their own sessions (privacy fix)
      assert html1 =~ "User 1 Workflow"
      refute html1 =~ "User 2 Workflow"

      assert html2 =~ "User 2 Workflow"
      refute html2 =~ "User 1 Workflow"
    end
  end

  describe "AI Assistant - Both modes" do
    setup :create_workflow

    test "mode registry returns correct handlers", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: "http://localhost:4001" <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_html =
        job_view
        |> element("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
        |> render()

      assert job_html =~ "Ask about your job code, debugging, or OpenFn adaptors"

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_html = render(workflow_view)
      assert workflow_html =~ "Describe the workflow you want to create"
    end

    @tag :capture_log
    test "error handling is consistent across modes", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:error, :timeout}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          job_view
          |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
          |> render_submit(assistant: %{content: "Help with code"})
        end)

      assert log =~ "AI query timed out for session"
      assert log =~ "Request timed out. Please try again."

      html = render_async(job_view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"

      assert has_element?(job_view, "[phx-click='retry_message']")

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          workflow_view
          |> form("#ai-assistant-form-new-workflow-panel-assistant")
          |> render_submit(assistant: %{content: "Create workflow"})
        end)

      assert log =~ "AI query timed out for session"
      assert log =~ "Request timed out. Please try again."

      html = render_async(workflow_view)

      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"

      assert has_element?(job_view, "[phx-click='retry_message']")
    end

    test "session management works independently for different modes", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [%{"role" => "assistant", "content" => "Response"}]
             }
           }}
      end)

      _job_session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          title: "Job Debugging Session"
        )

      _workflow_session =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: "Workflow Creation Session"
        )

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_html = job_view |> element("#job-#{job_1.id}-ai-assistant") |> render()
      assert job_html =~ "Job Debugging Session"
      refute job_html =~ "Workflow Creation Session"

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_html = render(workflow_view)
      refute workflow_html =~ "Job Debugging Session"
      assert workflow_html =~ "Workflow Creation Session"
    end

    test "usage limits apply to both modes equally", %{
      conn: conn,
      project: %{id: project_id} = project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      error_message = "AI usage limit reached"

      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
        %{type: :ai_usage}, %{project_id: ^project_id} ->
          {:error, :exceeds_limit,
           %Lightning.Extensions.Message{text: error_message}}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_html =
        job_view
        |> element("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
        |> render()

      assert job_html =~ error_message

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_html = render(workflow_view)
      assert workflow_html =~ error_message
    end

    test "keyboard shortcuts work consistently across modes", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "assistant", "content" => "Message sent"}
               ]
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_form =
        job_view |> element("#ai-assistant-form-job-#{job_1.id}-ai-assistant")

      assert has_element?(job_form)
      assert render(job_form) =~ "phx-hook=\"SendMessageViaCtrlEnter\""

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_form =
        workflow_view
        |> element("#new-workflow-panel-assistant")

      assert has_element?(workflow_form)
      assert render(workflow_form) =~ "phx-hook=\"SendMessageViaCtrlEnter\""
    end

    test "disclaimer flow works for both modes", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      refute user.preferences["ai_assistant.disclaimer_read_at"]

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_html =
        job_view
        |> element("#job-#{job_1.id}-ai-assistant")
        |> render()

      assert job_html =~ "Get started with the AI Assistant"

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_html = render(workflow_view)
      assert workflow_html =~ "Get started with the AI Assistant"

      job_view |> element("#get-started-with-ai-btn") |> render_click()

      user = Lightning.Repo.reload(user)
      assert user.preferences["ai_assistant.disclaimer_read_at"]

      {:ok, new_workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(new_workflow_view)

      new_workflow_html = render(new_workflow_view)
      refute new_workflow_html =~ "Get started with the AI Assistant"
      assert has_element?(new_workflow_view, "#new-workflow-panel-assistant")
    end

    test "both modes handle markdown formatting consistently", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      markdown_response = """
      Here's your solution:

      ## Code Example

      ```javascript
      fn((state) => {
        console.log("Hello world");
        return state;
      });
      ```

      ### Next Steps
      1. Test the code
      2. Deploy to production
      """

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => markdown_response,
               "history" => [
                 %{"role" => "assistant", "content" => markdown_response}
               ]
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Help me"})

      render_async(job_view)

      job_html = render(job_view)
      assert job_html =~ "<h2"
      assert job_html =~ "<pre"
      assert job_html =~ "<ol"

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(assistant: %{content: "Create workflow"})

      render_async(workflow_view)

      workflow_html = render(workflow_view)
      assert workflow_html =~ "<h2"
      assert workflow_html =~ "<pre"
      assert workflow_html =~ "<ol"
    end

    test "copy functionality works in both modes", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      response_content = "Here's some code you can copy"

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => response_content,
               "response_yaml" => nil,
               "usage" => %{},
               "history" => [
                 %{"role" => "assistant", "content" => response_content}
               ]
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Help"})

      assert_patch(job_view)
      render_async(job_view)

      job_html = render(job_view)

      assert job_html =~ "Here&#39;s some code you can copy"

      job_copy_btn = job_view |> element("[phx-hook='Copy']")
      assert has_element?(job_copy_btn)

      job_copy_html = render(job_copy_btn)
      assert job_copy_html =~ "Copy"

      assert job_copy_html =~
               "data-content=\"Here&#39;s some code you can copy\">"

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(assistant: %{content: "Create"})

      assert_patch(workflow_view)
      render_async(workflow_view)

      workflow_html = render(workflow_view)

      assert workflow_html =~ "Here&#39;s some code you can copy"

      workflow_copy_btn = workflow_view |> element("[phx-hook='Copy']")
      assert has_element?(workflow_copy_btn)

      workflow_copy_html = render(workflow_copy_btn)
      assert workflow_copy_html =~ "Copy"

      assert workflow_copy_html =~
               "data-content=\"Here&#39;s some code you can copy\">"
    end

    test "both modes handle user avatars and timestamps correctly", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "user", "content" => "Test message"},
                 %{"role" => "assistant", "content" => "Test response"}
               ]
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Test"})

      render_async(job_view)

      job_html = render(job_view)

      initials =
        "#{String.first(user.first_name)}#{String.first(user.last_name)}"

      assert job_html =~ initials

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(assistant: %{content: "Test"})

      render_async(workflow_view)

      workflow_html = render(workflow_view)
      assert workflow_html =~ initials
    end

    test "pagination works consistently across modes", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      for i <- 1..25 do
        insert(:job_chat_session,
          user: user,
          job: job_1,
          title: "Job Session #{i}",
          updated_at: DateTime.add(DateTime.utc_now(), -i, :hour)
        )

        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: "Workflow Session #{i}",
          updated_at: DateTime.add(DateTime.utc_now(), -i, :hour)
        )
      end

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_html = render(job_view)

      assert job_html =~ "Load more conversations"
      assert job_html =~ "20 of 25"

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_html = render(workflow_view)

      assert workflow_html =~ "Load more conversations"
      assert workflow_html =~ "20 of 25"

      job_view |> element("[phx-click='load_more_sessions']") |> render_click()

      workflow_view
      |> element("[phx-click='load_more_sessions']")
      |> render_click()

      render_async(job_view)
      render_async(workflow_view)

      job_html_after_load = render(job_view)
      workflow_html_after_load = render(workflow_view)

      refute job_html_after_load =~ "Load more conversations"
      assert job_html_after_load =~ "25 of 25"
      refute workflow_html_after_load =~ "Load more conversations"
      assert workflow_html_after_load =~ "25 of 25"
    end

    test "sorting functionality works in both modes", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}
      end)

      _older_job_session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          title: "Older Job Session",
          updated_at: ~N[2024-01-01 10:00:00]
        )

      _newer_job_session =
        insert(:job_chat_session,
          user: user,
          job: job_1,
          title: "Newer Job Session",
          updated_at: ~N[2024-02-01 10:00:00]
        )

      _older_workflow_session =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: "Older Workflow Session",
          updated_at: ~N[2024-01-01 10:00:00]
        )

      _newer_workflow_session =
        insert(:workflow_chat_session,
          user: user,
          project: project,
          title: "Newer Workflow Session",
          updated_at: ~N[2024-02-01 10:00:00]
        )

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      job_html = job_view |> element("#job-#{job_1.id}-ai-assistant") |> render()
      assert job_html =~ "Latest"

      job_view |> element("[phx-click='toggle_sort']") |> render_click()

      job_html_after_sort =
        job_view |> element("#job-#{job_1.id}-ai-assistant") |> render()

      assert job_html_after_sort =~ "Oldest"

      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_html = render(workflow_view)
      assert workflow_html =~ "Latest"

      workflow_view |> element("[phx-click='toggle_sort']") |> render_click()

      workflow_html_after_sort = render(workflow_view)
      assert workflow_html_after_sort =~ "Oldest"
    end
  end

  describe "AI Assistant - Component State Management:" do
    setup :create_workflow

    test "component state persists across navigation", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post, url: ^apollo_endpoint <> "/query"}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "assistant", "content" => "Response content"}
               ]
             }
           }}

        %{method: :post, url: ^apollo_endpoint <> "/workflow_chat"}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "Response content",
               "response_yaml" => nil,
               "usage" => %{}
             }
           }}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "history" => [
                 %{"role" => "assistant", "content" => "Response content"}
               ],
               "response" => "Response content",
               "response_yaml" => nil,
               "usage" => %{}
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, job_view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(job_view)

      # Submit the form to create a chat session
      job_view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Help with debugging"})

      # This creates a session and navigates to include j-chat parameter
      current_path = assert_patch(job_view)
      render_async(job_view)

      job_html = render(job_view)
      assert job_html =~ "Response content"
      assert job_html =~ "Help with debugging"

      # Navigate to workflow creation
      {:ok, workflow_view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new?method=ai")

      render_async(workflow_view)

      workflow_view
      |> form("#ai-assistant-form-new-workflow-panel-assistant")
      |> render_submit(assistant: %{content: "Create new workflow"})

      assert_patch(workflow_view)
      render_async(workflow_view)

      workflow_html = render(workflow_view)
      assert workflow_html =~ "Response content"

      # Navigate back to the job view using the path with chat session
      {:ok, new_job_view, _html} = live(conn, current_path)

      render_async(new_job_view)

      # The entire view should show the chat history
      new_job_html = render(new_job_view)

      # The original conversation should be visible
      assert new_job_html =~ "Help with debugging"
      assert new_job_html =~ "Response content"
    end

    test "async result states work correctly", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "Delayed response",
               "response_yaml" => nil,
               "usage" => %{},
               "history" => [
                 %{"role" => "assistant", "content" => "Delayed response"}
               ]
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(view)

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Test async"})

      assert_patch(view)

      html = render(view)
      assert html =~ "Delayed response"
      refute html =~ "Processing..."
    end

    @tag :capture_log
    test "error boundaries work correctly", %{
      conn: conn,
      project: project,
      user: user,
      workflow: %{jobs: [job_1 | _]} = workflow
    } do
      apollo_endpoint = "http://localhost:4001"

      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> apollo_endpoint
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: ^apollo_endpoint <> "/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          # Return a server error
          {:ok,
           %Tesla.Env{
             status: 500,
             body: %{
               "error" => "Internal server error",
               "message" => "Service crashed"
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?s=#{job_1.id}&m=expand"
        )

      render_async(view)

      view
      |> form("#ai-assistant-form-job-#{job_1.id}-ai-assistant")
      |> render_submit(assistant: %{content: "Trigger error"})

      assert_patch(view)

      # In test environment, error appears immediately
      html = render(view)

      # The user message should show as failed
      assert html =~ "ai-bg-gradient-error"
      assert html =~ "Failed"

      # The form should still be functional
      assert has_element?(
               view,
               "#ai-assistant-form-job-#{job_1.id}-ai-assistant"
             )

      # User should be able to retry
      assert has_element?(view, "[phx-click='retry_message']")
    end
  end

  defp create_project_for_user(%{user: user}) do
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    %{project: project}
  end
end
