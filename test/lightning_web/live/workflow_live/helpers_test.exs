defmodule LightningWeb.WorkflowLive.HelpersTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias LightningWeb.WorkflowLive.Helpers

  describe "collaborative_editor_url/1" do
    test "converts classical editor URL to collaborative for new workflow" do
      assigns = %{
        query_params: %{},
        project: %{id: "proj-1"},
        workflow: nil,
        live_action: :new
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/new/collaborate"
    end

    test "converts classical editor URL to collaborative for existing workflow" do
      assigns = %{
        query_params: %{},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate"
    end

    test "converts 'a' parameter (followed run) to 'run'" do
      assigns = %{
        query_params: %{"a" => "run-123"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?run=run-123"
    end

    test "converts 's' parameter to 'job' when selected_job exists" do
      assigns = %{
        query_params: %{"s" => "job-abc"},
        selected_job: %{id: "job-abc"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?job=job-abc"
    end

    test "converts 's' parameter to 'trigger' when selected_trigger exists" do
      assigns = %{
        query_params: %{"s" => "trigger-xyz"},
        selected_trigger: %{id: "trigger-xyz"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?trigger=trigger-xyz"
    end

    test "converts 's' parameter to 'edge' when selected_edge exists" do
      assigns = %{
        query_params: %{"s" => "edge-123"},
        selected_edge: %{id: "edge-123"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?edge=edge-123"
    end

    test "defaults 's' parameter to 'job' when no selection context" do
      assigns = %{
        query_params: %{"s" => "unknown-id"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?job=unknown-id"
    end

    test "converts 'm=expand' to 'panel=editor'" do
      assigns = %{
        query_params: %{"m" => "expand"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?panel=editor"
    end

    test "converts 'm=workflow_input' to 'panel=run'" do
      assigns = %{
        query_params: %{"m" => "workflow_input"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?panel=run"
    end

    test "converts 'm=settings' to 'panel=settings'" do
      assigns = %{
        query_params: %{"m" => "settings"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?panel=settings"
    end

    test "preserves 'v' parameter (version tag)" do
      assigns = %{
        query_params: %{"v" => "snapshot-123"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?v=snapshot-123"
    end

    test "preserves 'method' parameter" do
      assigns = %{
        query_params: %{"method" => "some-method"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?method=some-method"
    end

    test "preserves 'w-chat' parameter" do
      assigns = %{
        query_params: %{"w-chat" => "chat-123"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?w-chat=chat-123"
    end

    test "preserves 'j-chat' parameter" do
      assigns = %{
        query_params: %{"j-chat" => "chat-456"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?j-chat=chat-456"
    end

    test "preserves 'code' parameter" do
      assigns = %{
        query_params: %{"code" => "some-code"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?code=some-code"
    end

    test "skips 'panel' parameter (collaborative-only)" do
      assigns = %{
        query_params: %{"panel" => "run"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate"
    end

    test "preserves unknown parameters for future compatibility" do
      assigns = %{
        query_params: %{"unknown" => "value"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate?unknown=value"
    end

    test "handles multiple parameters with complex conversion" do
      assigns = %{
        query_params: %{
          "a" => "run-123",
          "s" => "job-abc",
          "m" => "expand",
          "v" => "latest",
          "w-chat" => "chat-123"
        },
        selected_job: %{id: "job-abc"},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)

      # Check that all expected parameters are present
      assert result =~ "/projects/proj-1/w/wf-1/collaborate?"
      assert result =~ "run=run-123"
      assert result =~ "job=job-abc"
      assert result =~ "panel=editor"
      assert result =~ "v=latest"
      assert result =~ "w-chat=chat-123"
    end

    test "handles nil parameter values gracefully" do
      assigns = %{
        query_params: %{"a" => nil, "s" => nil},
        project: %{id: "proj-1"},
        workflow: %{id: "wf-1"},
        live_action: :edit
      }

      result = Helpers.collaborative_editor_url(assigns)
      assert result == "/projects/proj-1/w/wf-1/collaborate"
    end
  end

  describe "show_collaborative_editor_toggle?/2" do
    test "returns true when user has experimental features and viewing latest" do
      user = insert(:user, preferences: %{"experimental_features" => true})

      result = Helpers.show_collaborative_editor_toggle?(user, "latest")
      assert result == true
    end

    test "returns false when user doesn't have experimental features" do
      user = insert(:user, preferences: %{"experimental_features" => false})

      result = Helpers.show_collaborative_editor_toggle?(user, "latest")
      assert result == false
    end

    test "returns false when viewing a snapshot (not latest)" do
      user = insert(:user, preferences: %{"experimental_features" => true})

      result = Helpers.show_collaborative_editor_toggle?(user, "snapshot-123")
      assert result == false
    end

    test "returns false when both conditions fail" do
      user = insert(:user, preferences: %{"experimental_features" => false})

      result = Helpers.show_collaborative_editor_toggle?(user, "snapshot-123")
      assert result == false
    end
  end

  describe "workflow_enabled?/1" do
    test "returns true when all triggers are enabled (Workflow struct)" do
      workflow = %Lightning.Workflows.Workflow{
        triggers: [
          %{enabled: true},
          %{enabled: true}
        ]
      }

      assert Helpers.workflow_enabled?(workflow) == true
    end

    test "returns false when any trigger is disabled (Workflow struct)" do
      workflow = %Lightning.Workflows.Workflow{
        triggers: [
          %{enabled: true},
          %{enabled: false}
        ]
      }

      assert Helpers.workflow_enabled?(workflow) == false
    end

    test "returns true when workflow has no triggers (Workflow struct)" do
      workflow = %Lightning.Workflows.Workflow{
        triggers: []
      }

      assert Helpers.workflow_enabled?(workflow) == true
    end

    test "returns true when all triggers are enabled (Changeset)" do
      changeset =
        Ecto.Changeset.change(%Lightning.Workflows.Workflow{}, %{
          triggers: [
            %{enabled: true},
            %{enabled: true}
          ]
        })

      assert Helpers.workflow_enabled?(changeset) == true
    end

    test "returns false when any trigger is disabled (Changeset)" do
      changeset =
        Ecto.Changeset.change(%Lightning.Workflows.Workflow{}, %{
          triggers: [
            %{enabled: true},
            %{enabled: false}
          ]
        })

      assert Helpers.workflow_enabled?(changeset) == false
    end
  end

  describe "workflow_state_tooltip/1" do
    test "returns inactive message when no triggers configured (Workflow struct)" do
      workflow = %Lightning.Workflows.Workflow{
        triggers: []
      }

      result = Helpers.workflow_state_tooltip(workflow)
      assert result == "This workflow is inactive (no triggers configured)"
    end

    test "returns active message with trigger type when all enabled (Workflow struct)" do
      workflow = %Lightning.Workflows.Workflow{
        triggers: [
          %{enabled: true, type: :webhook},
          %{enabled: true, type: :cron}
        ]
      }

      result = Helpers.workflow_state_tooltip(workflow)
      assert result == "This workflow is active (webhook trigger enabled)"
    end

    test "returns inactive message when triggers disabled (Workflow struct)" do
      workflow = %Lightning.Workflows.Workflow{
        triggers: [
          %{enabled: false, type: :webhook}
        ]
      }

      result = Helpers.workflow_state_tooltip(workflow)
      assert result == "This workflow is inactive (manual runs only)"
    end

    test "returns inactive message when no triggers configured (Changeset)" do
      changeset =
        Ecto.Changeset.change(%Lightning.Workflows.Workflow{}, %{
          triggers: []
        })

      result = Helpers.workflow_state_tooltip(changeset)
      assert result == "This workflow is inactive (no triggers configured)"
    end

    test "returns active message with trigger type when all enabled (Changeset)" do
      changeset =
        Ecto.Changeset.change(%Lightning.Workflows.Workflow{}, %{
          triggers: [
            %{enabled: true, type: :webhook}
          ]
        })

      result = Helpers.workflow_state_tooltip(changeset)
      assert result == "This workflow is active (webhook trigger enabled)"
    end

    test "returns inactive message when triggers disabled (Changeset)" do
      changeset =
        Ecto.Changeset.change(%Lightning.Workflows.Workflow{}, %{
          triggers: [
            %{enabled: false, type: :webhook}
          ]
        })

      result = Helpers.workflow_state_tooltip(changeset)
      assert result == "This workflow is inactive (manual runs only)"
    end
  end

  describe "build_url/2" do
    test "builds URL with simple static values" do
      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      params = [
        Helpers.param("foo", "bar"),
        Helpers.param("baz", "qux")
      ]

      result = Helpers.build_url(assigns, params)
      assert result =~ "/test?"
      assert result =~ "foo=bar"
      assert result =~ "baz=qux"
    end

    test "builds URL with function values (arity 2)" do
      assigns = %{
        base_url: "/test",
        query_params: %{"existing" => "value"},
        custom_field: "custom"
      }

      params = [
        Helpers.param("key", fn a, _p -> a.custom_field end)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test?key=custom"
    end

    test "builds URL with function values (arity 1)" do
      assigns = %{
        base_url: "/test",
        query_params: %{},
        custom_field: "custom"
      }

      params = [
        Helpers.param("key", fn a -> a.custom_field end)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test?key=custom"
    end

    test "builds URL with function values (arity 0)" do
      params = [
        Helpers.param("key", fn -> "static" end)
      ]

      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      result = Helpers.build_url(assigns, params)
      assert result == "/test?key=static"
    end

    test "builds URL with conditional when clause (boolean)" do
      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      params = [
        Helpers.param("included", "yes", when: true),
        Helpers.param("excluded", "no", when: false)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test?included=yes"
      refute result =~ "excluded"
    end

    test "builds URL with conditional when clause (function arity 2)" do
      assigns = %{
        base_url: "/test",
        query_params: %{},
        should_include: true
      }

      params = [
        Helpers.param("test", "value", when: fn a, _p -> a.should_include end)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test?test=value"
    end

    test "builds URL with conditional when clause (function arity 1)" do
      assigns = %{
        base_url: "/test",
        query_params: %{},
        should_include: true
      }

      params = [
        Helpers.param("test", "value", when: fn a -> a.should_include end)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test?test=value"
    end

    test "builds URL with conditional when clause (function arity 0)" do
      params = [
        Helpers.param("test", "value", when: fn -> true end)
      ]

      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      result = Helpers.build_url(assigns, params)
      assert result == "/test?test=value"
    end

    test "builds URL with transform function" do
      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      params = [
        Helpers.param("upper", "hello", transform: &String.upcase/1)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test?upper=HELLO"
    end

    test "excludes nil values from URL" do
      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      params = [
        Helpers.param("present", "value"),
        Helpers.param("absent", nil)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test?present=value"
      refute result =~ "absent"
    end

    test "returns base URL when no parameters" do
      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      result = Helpers.build_url(assigns, [])
      assert result == "/test"
    end

    test "returns base URL when all parameters excluded" do
      assigns = %{
        base_url: "/test",
        query_params: %{}
      }

      params = [
        Helpers.param("excluded", "value", when: false),
        Helpers.param("nil", nil)
      ]

      result = Helpers.build_url(assigns, params)
      assert result == "/test"
    end
  end

  describe "query_param/1" do
    test "creates parameter that reads from query_params" do
      param = Helpers.query_param("test")

      assigns = %{query_params: %{"test" => "value"}}
      value = Keyword.fetch!(param, :value)
      result = value.(assigns, [])

      assert result == "value"
    end
  end

  describe "chat_params/0" do
    test "returns w-chat and j-chat parameters" do
      params = Helpers.chat_params()

      assert length(params) == 2
      assert Enum.any?(params, fn p -> Keyword.get(p, :name) == "w-chat" end)
      assert Enum.any?(params, fn p -> Keyword.get(p, :name) == "j-chat" end)
    end
  end

  describe "with_params/1" do
    test "merges override parameters with standard params" do
      assigns = %{
        base_url: "/test",
        query_params: %{"m" => "expand", "s" => "job-1"},
        workflow_chat_session_id: nil,
        job_chat_session_id: nil
      }

      params = Helpers.with_params(custom: "value")
      result = Helpers.build_url(assigns, params)

      assert result =~ "custom=value"
      assert result =~ "m=expand"
      assert result =~ "s=job-1"
    end

    test "override values replace standard params" do
      assigns = %{
        base_url: "/test",
        query_params: %{"m" => "expand"},
        workflow_chat_session_id: nil,
        job_chat_session_id: nil
      }

      params = Helpers.with_params(m: "settings")
      result = Helpers.build_url(assigns, params)

      assert result == "/test?m=settings"
      refute result =~ "m=expand"
    end
  end
end
