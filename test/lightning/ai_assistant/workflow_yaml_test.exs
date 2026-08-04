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

  # Helpers for the "hostile input" describe below: a minimal valid state
  # map (the Y.Doc-deserialized shape) that individual tests override to
  # inject hostile values.
  defp hostile_state(overrides) do
    Map.merge(
      %{
        "id" => "00000000-0000-4000-8000-000000000000",
        "name" => "Hostile Workflow",
        "jobs" => [job_entry(%{})],
        "triggers" => [
          %{
            "id" => trigger_id(),
            "type" => "webhook",
            "enabled" => true,
            "webhook_reply" => nil,
            "webhook_response_config" => nil
          }
        ],
        "edges" => [edge_entry(%{})],
        "positions" => nil
      },
      overrides
    )
  end

  defp job_id, do: "11111111-1111-4111-8111-111111111111"
  defp job2_id, do: "22222222-2222-4222-8222-222222222222"
  defp trigger_id, do: "33333333-3333-4333-8333-333333333333"

  defp job_entry(overrides) do
    Map.merge(
      %{
        "id" => job_id(),
        "name" => "Job One",
        "adaptor" => "@openfn/language-common@latest",
        "body" => "fn(s => s);"
      },
      overrides
    )
  end

  defp edge_entry(overrides) do
    Map.merge(
      %{
        "id" => "44444444-4444-4444-8444-444444444444",
        "condition_type" => "always",
        "condition_label" => nil,
        "condition_expression" => nil,
        "enabled" => true,
        "source_trigger_id" => trigger_id(),
        "source_job_id" => nil,
        "target_job_id" => job_id()
      },
      overrides
    )
  end

  defp serialize_and_parse(state) do
    yaml = WorkflowYAML.serialize(state)
    assert is_binary(yaml)
    YamlElixir.read_from_string!(yaml)
  end

  describe "serialize/1 with hostile input" do
    test "a job body with a bare CR round-trips through the quoted fallback" do
      body = "a\rb\nc"

      parsed =
        serialize_and_parse(
          hostile_state(%{"jobs" => [job_entry(%{"body" => body})]})
        )

      # A bare CR is invalid inside a block scalar, so the value must take
      # the quoted fallback and come back byte-for-byte.
      assert get_in(parsed, ["jobs", "Job-One", "body"]) == body
    end

    test "a job body with CRLF line endings round-trips byte-for-byte" do
      body = "line1\r\nline2"

      parsed =
        serialize_and_parse(
          hostile_state(%{"jobs" => [job_entry(%{"body" => body})]})
        )

      # A block scalar would silently normalize the CRLF away; the quoted
      # fallback escapes it instead.
      assert get_in(parsed, ["jobs", "Job-One", "body"]) == body
    end

    test "jobs whose names hyphenate to the same key keep the last one" do
      parsed =
        serialize_and_parse(
          hostile_state(%{
            "jobs" => [
              job_entry(%{"name" => "My Job", "body" => "first()"}),
              job_entry(%{
                "id" => job2_id(),
                "name" => "My-Job",
                "body" => "second()"
              })
            ]
          })
        )

      # Duplicate mapping keys would make the client's own YAML.parse throw;
      # the client's JS object assignment keeps the last write, so match it.
      assert %{"My-Job" => job_spec} = parsed["jobs"]
      assert map_size(parsed["jobs"]) == 1
      assert job_spec["id"] == job2_id()
      assert job_spec["body"] == "second()"
    end

    test "edges that collide on source->target keep the last one" do
      parsed =
        serialize_and_parse(
          hostile_state(%{
            "edges" => [
              edge_entry(%{"condition_type" => "on_job_success"}),
              edge_entry(%{
                "id" => "55555555-5555-4555-8555-555555555555",
                "condition_type" => "on_job_failure"
              })
            ]
          })
        )

      assert %{"webhook->Job-One" => edge_spec} = parsed["edges"]
      assert map_size(parsed["edges"]) == 1
      assert edge_spec["id"] == "55555555-5555-4555-8555-555555555555"
      assert edge_spec["condition_type"] == "on_job_failure"
    end

    test "a nil job name is keyed as an empty string, not a null key" do
      parsed =
        serialize_and_parse(
          hostile_state(%{"jobs" => [job_entry(%{"name" => nil})]})
        )

      assert %{"" => job_spec} = parsed["jobs"]
      assert job_spec["id"] == job_id()
      assert job_spec["name"] == nil
    end

    test "DEL, C1 controls and Unicode line separators are escaped" do
      # PyYAML hard-rejects raw 0x7F and folds U+0085 into a space, so the
      # quoted fallback must escape them beyond what Jason does.
      body = "a\d\nb\u{0085}c\u{2028}d"

      yaml =
        WorkflowYAML.serialize(
          hostile_state(%{"jobs" => [job_entry(%{"body" => body})]})
        )

      refute yaml =~ "\d"
      refute yaml =~ "\u{0085}"
      refute yaml =~ "\u{2028}"

      assert get_in(YamlElixir.read_from_string!(yaml), [
               "jobs",
               "Job-One",
               "body"
             ]) == body
    end
  end
end
