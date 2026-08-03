defmodule Lightning.AiAssistant.WorkflowYAMLTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.AiAssistant.WorkflowYAML

  describe "serialize/1 with a saved workflow" do
    test "mirrors the client spec shape (convertWorkflowStateToSpec with ids)" do
      trigger = build(:trigger, type: :webhook, enabled: true)

      job =
        build(:job,
          name: "Fetch Data",
          adaptor: "@openfn/language-http@latest",
          body: "fn(state => {\n  return state;\n});"
        )

      workflow =
        build(:workflow, name: "My Test Workflow")
        |> with_trigger(trigger)
        |> with_job(job)
        |> with_edge({trigger, job}, condition_type: :always)
        |> insert()

      workflow = %{
        workflow
        | positions: %{
            job.id => %{"x" => 100.4, "y" => 200},
            trigger.id => %{"x" => 100, "y" => 50}
          }
      }

      yaml = WorkflowYAML.serialize(workflow)

      assert is_binary(yaml)

      parsed = YamlElixir.read_from_string!(yaml)

      # Top-level keys match the client-produced spec
      assert %{
               "id" => workflow_id,
               "name" => "My Test Workflow",
               "jobs" => jobs,
               "triggers" => triggers,
               "edges" => edges
             } = parsed

      assert workflow_id == workflow.id

      # Jobs are keyed by hyphenated name and carry id/name/adaptor/body/pos
      assert %{
               "Fetch-Data" => %{
                 "id" => job_id,
                 "name" => "Fetch Data",
                 "adaptor" => "@openfn/language-http@latest",
                 "body" => "fn(state => {\n  return state;\n});",
                 "pos" => %{"x" => 100, "y" => 200}
               }
             } = jobs

      assert job_id == job.id

      # Triggers are keyed by type; webhook triggers carry webhook_reply
      assert %{
               "webhook" => %{
                 "id" => trigger_id,
                 "type" => "webhook",
                 "enabled" => true,
                 "webhook_reply" => "before_start",
                 "pos" => %{"x" => 100, "y" => 50}
               }
             } = triggers

      assert trigger_id == trigger.id

      # Edges are keyed by source->target with hyphenated names
      assert %{
               "webhook->Fetch-Data" => %{
                 "condition_type" => "always",
                 "enabled" => true,
                 "source_trigger" => "webhook",
                 "target_job" => "Fetch-Data"
               }
             } = edges
    end

    test "serializes an empty workflow to a valid spec" do
      workflow = insert(:workflow, name: "Empty Workflow")
      workflow = Repo.preload(workflow, [:jobs, :triggers, :edges])

      yaml = WorkflowYAML.serialize(workflow)

      assert %{
               "id" => _,
               "name" => "Empty Workflow",
               "jobs" => %{},
               "triggers" => %{},
               "edges" => %{}
             } = YamlElixir.read_from_string!(yaml)
    end
  end

  describe "serialize/1 with a Y.Doc-deserialized state map" do
    test "produces the same spec shape from string-keyed state" do
      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      state = %{
        "id" => Ecto.UUID.generate(),
        "name" => "Live Workflow",
        "jobs" => [
          %{
            "id" => job_id,
            "name" => "Do Things",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "fn(s => s);",
            "project_credential_id" => nil,
            "keychain_credential_id" => nil
          }
        ],
        "triggers" => [
          %{
            "id" => trigger_id,
            "type" => "cron",
            "enabled" => false,
            "cron_expression" => "0 * * * *",
            "cron_cursor_job_id" => job_id,
            "webhook_reply" => nil,
            "webhook_response_config" => nil,
            "kafka_configuration" => nil
          }
        ],
        "edges" => [
          %{
            "id" => edge_id,
            "condition_type" => "js_expression",
            "condition_label" => "on success",
            "condition_expression" => "state.ok",
            "enabled" => true,
            "source_trigger_id" => trigger_id,
            "source_job_id" => nil,
            "target_job_id" => job_id
          }
        ],
        "positions" => %{job_id => %{"x" => 10.6, "y" => 20.2}}
      }

      parsed =
        state |> WorkflowYAML.serialize() |> YamlElixir.read_from_string!()

      assert %{"jobs" => %{"Do-Things" => job_spec}} = parsed
      assert job_spec["pos"] == %{"x" => 11, "y" => 20}

      assert %{
               "triggers" => %{
                 "cron" => %{
                   "type" => "cron",
                   "enabled" => false,
                   "cron_expression" => "0 * * * *",
                   "cron_cursor_job" => "Do-Things"
                 }
               }
             } = parsed

      assert %{
               "edges" => %{
                 "cron->Do-Things" => %{
                   "id" => ^edge_id,
                   "condition_type" => "js_expression",
                   "condition_label" => "on success",
                   "condition_expression" => "state.ok",
                   "source_trigger" => "cron",
                   "target_job" => "Do-Things"
                 }
               }
             } = parsed
    end
  end
end
