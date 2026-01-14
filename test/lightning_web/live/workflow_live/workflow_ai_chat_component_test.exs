defmodule LightningWeb.WorkflowLive.WorkflowAiChatComponentTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Mox
  import Ecto.Query

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :verify_on_exit!

  setup %{project: project} do
    workflow = insert(:simple_workflow, project: project)
    {:ok, snapshot} = Lightning.Workflows.Snapshot.create(workflow)

    # Stub Apollo as online
    Mox.stub(Lightning.MockConfig, :apollo, fn
      :endpoint -> "http://localhost:4001"
      :ai_assistant_api_key -> "test_api_key"
      :timeout -> 5_000
    end)

    %{workflow: workflow, snapshot: snapshot}
  end

  defp skip_disclaimer(user, read_at \\ DateTime.utc_now() |> DateTime.to_unix()) do
    Ecto.Changeset.change(user, %{
      preferences: %{"ai_assistant.disclaimer_read_at" => read_at}
    })
    |> Lightning.Repo.update!()
  end

  describe "component mounting and rendering" do
    test "renders the AI chat panel with correct structure", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai")

      assert has_element?(view, "#workflow-ai-chat-panel")
      assert has_element?(view, "#workflow-ai-chat-panel-assistant")
    end
  end

  describe "AI workflow generation" do
    test "generates and applies valid workflow template", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      valid_workflow_yaml = """
      name: Updated Workflow
      jobs:
        fetch_data:
          name: Fetch Data
          adaptor: '@openfn/language-http@latest'
          body: |
            get('/api/data');
      triggers:
        webhook:
          type: webhook
          enabled: true
      edges:
        webhook->fetch_data:
          source_trigger: webhook
          target_job: fetch_data
          condition_type: always
      """

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: "http://localhost:4001/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "I'll update your workflow",
               "response_yaml" => valid_workflow_yaml,
               "usage" => %{},
               "history" => [
                 %{"role" => "user", "content" => "Add a fetch data job"},
                 %{
                   "role" => "assistant",
                   "content" => "I'll update your workflow"
                 }
               ]
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai")

      render_async(view)

      view
      |> element("#ai-assistant-form-workflow-ai-chat-panel-assistant")
      |> render_submit(%{"assistant" => %{"content" => "Add a fetch data job"}})

      assert_push_event(view, "template_selected", %{template: template})
      assert template =~ "name: Updated Workflow"
      assert template =~ "fetch_data"

      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      parsed_params = %{
        "name" => "Updated Workflow",
        "jobs" => [
          %{
            "id" => job_id,
            "name" => "Fetch Data",
            "adaptor" => "@openfn/language-http@latest",
            "body" => "get('/api/data');"
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
            "id" => edge_id,
            "source_trigger_id" => trigger_id,
            "target_job_id" => job_id,
            "condition_type" => "always"
          }
        ]
      }

      ExUnit.CaptureLog.capture_log(fn ->
        view
        |> with_target("#workflow-ai-chat-panel")
        |> render_hook("template-parsed", %{"workflow" => parsed_params})
      end)

      assert_receive {_ref,
                      {:push_event, "template_selected", %{template: template}}}

      assert template =~ "Updated Workflow"
    end

    test "handles YAML parse errors from JavaScript", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      invalid_yaml = """
      name: Bad Workflow
      jobs:
        - this is invalid yaml structure
          body: |
      """

      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: "http://localhost:4001/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "Here's your workflow",
               "response_yaml" => invalid_yaml,
               "usage" => %{}
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai")

      render_async(view)

      view
      |> element("#ai-assistant-form-workflow-ai-chat-panel-assistant")
      |> render_submit(%{"assistant" => %{"content" => "Create a bad workflow"}})

      assert_push_event(view, "template_selected", %{template: template})
      assert template =~ "Bad Workflow"

      message =
        Lightning.Repo.one(
          from(m in Lightning.AiAssistant.ChatMessage,
            where: m.role == :assistant,
            order_by: [desc: m.inserted_at],
            limit: 1
          )
        )

      view
      |> element(
        "[phx-click='select_assistant_message'][phx-value-message-id='#{message.id}']"
      )
      |> render_click()

      ExUnit.CaptureLog.capture_log(fn ->
        view
        |> with_target("#workflow-ai-chat-panel")
        |> render_hook("template-parse-error", %{
          "error" => "Invalid YAML: unexpected scalar at line 3"
        })
      end)

      html = render(view)
      assert html =~ "Error while parsing workflow"
      assert html =~ "Click to view error details"

      assert has_element?(view, "#error-details-#{message.id}")
      assert html =~ "Invalid YAML: unexpected scalar at line 3"
    end

    test "handles validation errors when parsed workflow is invalid", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: "http://localhost:4001/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "Here's a workflow with validation issues",
               "response_yaml" => """
               name: ""
               jobs:
                 empty_job:
                   name: ""
                   adaptor: ""
                   body: ""
               """,
               "usage" => %{}
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai")

      render_async(view)

      view
      |> element("#ai-assistant-form-workflow-ai-chat-panel-assistant")
      |> render_submit(%{
        "assistant" => %{"content" => "Create invalid workflow"}
      })

      assert_push_event(view, "template_selected", %{template: _})

      render_async(view)

      message =
        Lightning.Repo.one(
          from(m in Lightning.AiAssistant.ChatMessage,
            where: m.role == :assistant,
            order_by: [desc: m.inserted_at],
            limit: 1
          )
        )

      view
      |> element(
        "[phx-click='select_assistant_message'][phx-value-message-id='#{message.id}']"
      )
      |> render_click()

      invalid_params = %{
        "name" => "",
        "jobs" => [
          %{
            "id" => Ecto.UUID.generate(),
            "name" => "",
            "adaptor" => "",
            "body" => ""
          }
        ]
      }

      ExUnit.CaptureLog.capture_log(fn ->
        view
        |> with_target("#workflow-ai-chat-panel")
        |> render_hook("template-parsed", %{"workflow" => invalid_params})
      end)

      html = render_async(view)

      assert html =~ "Error while parsing workflow"

      assert has_element?(view, "button[phx-click*='error-details']")
      assert has_element?(view, "#error-details-#{message.id}")

      assert html =~ "name - can&#39;t be blank"
      assert html =~ "jobs.1.body - job body can&#39;t be blank"
      assert html =~ "jobs.1.name - job name can&#39;t be blank"
    end

    test "clicking on AI message with code restores workflow", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      skip_disclaimer(user)

      session =
        insert(:chat_session,
          project: project,
          workflow: workflow,
          user: user,
          session_type: "workflow_template"
        )

      workflow_code = """
      name: Previous Workflow
      jobs:
        old_job:
          name: Old Job
          adaptor: '@openfn/language-common@latest'
          body: |
            console.log("old");
      """

      message =
        insert(:chat_message,
          chat_session: session,
          role: :assistant,
          content: "Here's your previous workflow",
          code: workflow_code
        )

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai&w-chat=#{session.id}"
        )

      assert_push_event(view, "template_selected", %{template: ^workflow_code})

      view
      |> element(
        "[phx-click='select_assistant_message'][phx-value-message-id='#{message.id}']"
      )
      |> render_click()

      assert_push_event(view, "template_selected", %{template: ^workflow_code})
    end
  end

  describe "complex validation error scenarios" do
    test "handles multiple job errors with proper naming", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        workflow_yaml = """
        name: Multi-job Workflow
        jobs:
          first_job:
            name: First Job
            adaptor: ""
            body: console.log('valid');
          second_job:
            name: Second Job
            adaptor: @openfn/language-common@latest
            body: ""
          third_job:
            name: ""
            adaptor: @openfn/language-common@latest
            body: fn(state => state)
        triggers:
          webhook:
            type: webhook
        edges:
          webhook->first_job:
            source_trigger: webhook
            target_job: first_job
        """

        Mox.stub(Lightning.MockConfig, :apollo, fn key ->
          case key do
            :endpoint -> "http://localhost:3000"
            :ai_assistant_api_key -> "api_key"
            :timeout -> 5_000
          end
        end)

        Mox.stub(Lightning.Tesla.Mock, :call, fn
          %{method: :get, url: "http://localhost:3000/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "response" => "Here's a workflow with validation issues",
                 "response_yaml" => workflow_yaml,
                 "usage" => %{},
                 "history" => [
                   %{
                     "role" => "user",
                     "content" => "Create workflow with errors"
                   },
                   %{
                     "role" => "assistant",
                     "content" => "Here's a workflow with validation issues"
                   }
                 ]
               }
             }}
        end)

        skip_disclaimer(user)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai"
          )

        render_async(view)

        view
        |> form("#ai-assistant-form-workflow-ai-chat-panel-assistant")
        |> render_submit(%{
          assistant: %{content: "Create workflow with errors"}
        })

        render_async(view)

        assert_push_event(view, "template_selected", %{template: template})
        assert template =~ workflow_yaml

        message =
          Lightning.Repo.one(
            from(m in Lightning.AiAssistant.ChatMessage,
              where: m.role == :assistant,
              order_by: [desc: m.inserted_at],
              limit: 1
            )
          )

        element(
          view,
          "div[phx-value-message-id='#{message.id}']"
        )
        |> render_click()

        params_with_job_errors = %{
          "name" => "Multi-job Workflow",
          "jobs" => [
            %{
              "id" => Ecto.UUID.generate(),
              "name" => "First Job",
              "adaptor" => "",
              "body" => "console.log('valid');"
            },
            %{
              "id" => Ecto.UUID.generate(),
              "name" => "Second Job",
              "adaptor" => "@openfn/language-common@latest",
              "body" => ""
            },
            %{
              "id" => Ecto.UUID.generate(),
              "name" => "",
              "adaptor" => "@openfn/language-common@latest",
              "body" => "fn(state => state)"
            }
          ],
          "triggers" => [
            %{
              "id" => Ecto.UUID.generate(),
              "type" => "webhook"
            }
          ],
          "edges" => [
            %{
              "id" => Ecto.UUID.generate(),
              "source_trigger_id" => "trigger-id",
              "target_job_id" => "job-id"
            }
          ]
        }

        log =
          ExUnit.CaptureLog.capture_log(fn ->
            view
            |> with_target("#workflow-ai-chat-panel")
            |> render_hook("template-parsed", %{
              "workflow" => params_with_job_errors
            })
          end)

        assert log =~
                 "Workflow code parse failed:"

        html = render(view)

        assert html =~ "Error while parsing workflow"

        assert has_element?(view, "button[phx-click*='error-details']")
        assert has_element?(view, "#error-details-#{message.id}")

        assert html =~ "job name can&#39;t be blank"
      end)
    end

    test "handles workflow yaml parse errors", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        workflow_yaml = "unparseable workflow"

        Mox.stub(Lightning.MockConfig, :apollo, fn key ->
          case key do
            :endpoint -> "http://localhost:3000"
            :ai_assistant_api_key -> "api_key"
            :timeout -> 5_000
          end
        end)

        Mox.stub(Lightning.Tesla.Mock, :call, fn
          %{method: :get, url: "http://localhost:3000/"}, _opts ->
            {:ok, %Tesla.Env{status: 200}}

          %{method: :post}, _opts ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: %{
                 "response" => "Here's a workflow with validation issues",
                 "response_yaml" => workflow_yaml,
                 "usage" => %{},
                 "history" => [
                   %{
                     "role" => "user",
                     "content" => "Create workflow with errors"
                   },
                   %{
                     "role" => "assistant",
                     "content" => "Here's a workflow with validation issues"
                   }
                 ]
               }
             }}
        end)

        skip_disclaimer(user)

        {:ok, view, _html} =
          live(
            conn,
            ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai"
          )

        render_async(view)

        view
        |> form("#ai-assistant-form-workflow-ai-chat-panel-assistant")
        |> render_submit(%{
          assistant: %{content: "Create workflow with errors"}
        })

        render_async(view)

        assert_push_event(view, "template_selected", %{template: template})
        assert template =~ workflow_yaml

        message =
          Lightning.Repo.one(
            from(m in Lightning.AiAssistant.ChatMessage,
              where: m.role == :assistant,
              order_by: [desc: m.inserted_at],
              limit: 1
            )
          )

        element(
          view,
          "div[phx-value-message-id='#{message.id}']"
        )
        |> render_click()

        log =
          ExUnit.CaptureLog.capture_log(fn ->
            view
            |> with_target("#workflow-ai-chat-panel")
            |> render_hook("template-parse-error", %{
              "error" => "workflow format unknown"
            })
          end)

        assert log =~ "Workflow code parse failed: \"workflow format unknown\""

        html = render(view)

        assert html =~ "Error while parsing workflow"

        assert has_element?(view, "button[phx-click*='error-details']")
        assert has_element?(view, "#error-details-#{message.id}")

        assert html =~ "workflow format unknown"
      end)
    end
  end

  describe "AI assistant state management" do
    test "shows loading state when sending message", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      Mox.stub(Lightning.Tesla.Mock, :call, fn
        %{method: :get, url: "http://localhost:4001/"}, _opts ->
          {:ok, %Tesla.Env{status: 200}}

        %{method: :post}, _opts ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "response" => "Processing...",
               "response_yaml" => nil,
               "usage" => %{}
             }
           }}
      end)

      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai")

      render_async(view)

      view
      |> element("#ai-assistant-form-workflow-ai-chat-panel-assistant")
      |> render_submit(%{"assistant" => %{"content" => "Update workflow"}})

      # Canvas should be notified about sending state - we disable when we send the message
      assert_receive {_ref, {:push_event, "set-disabled", %{disabled: true}}}

      # Canvas should be notified when done - we enable when we receive the message
      assert_receive {_ref, {:push_event, "set-disabled", %{disabled: false}}}
    end

    test "preserves workflow params between updates", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai")

      job_id = Ecto.UUID.generate()

      initial_params = %{
        "name" => "Initial Workflow",
        "jobs" => [
          %{
            "id" => job_id,
            "name" => "Initial Job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(state => state)"
          }
        ]
      }

      ExUnit.CaptureLog.capture_log(fn ->
        view
        |> with_target("#workflow-ai-chat-panel")
        |> render_hook("template-parsed", %{"workflow" => initial_params})
      end)

      assert_receive {_ref, {:push_event, "patches-applied", _patches}}

      # Send same params again - should not trigger update
      ExUnit.CaptureLog.capture_log(fn ->
        view
        |> with_target("#workflow-ai-chat-panel")
        |> render_hook("template-parsed", %{"workflow" => initial_params})
      end)

      # Should not receive another notification
      refute_receive {_ref, {:push_event, "patches-applied", _patches}}
    end
  end

  describe "error logging" do
    test "logs YAML parse errors", %{
      conn: conn,
      project: project,
      workflow: workflow,
      user: user
    } do
      skip_disclaimer(user)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/w/#{workflow}/legacy?method=ai")

      import ExUnit.CaptureLog

      log =
        capture_log(fn ->
          view
          |> with_target("#workflow-ai-chat-panel")
          |> render_hook("template-parse-error", %{
            "error" => "YAML syntax error at line 42: unexpected end of stream"
          })
        end)

      assert log =~ "Workflow code parse failed"
      assert log =~ "YAML syntax error at line 42"
    end
  end
end
