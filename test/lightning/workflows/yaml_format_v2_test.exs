defmodule Lightning.Workflows.YamlFormatV2Test do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.YamlFormat.V2

  import Lightning.Factories

  describe "serialize_workflow/1 from a Workflow struct" do
    setup do
      job_a =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "step alpha",
          adaptor: "@openfn/language-http@latest",
          body: "fn(state => state)\n"
        )

      job_b =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "step beta",
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)\n"
        )

      trigger =
        build(:trigger, id: Ecto.UUID.generate(), type: :webhook, enabled: true)

      edge_t =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: trigger.id,
          source_job_id: nil,
          target_job_id: job_a.id,
          condition_type: :always,
          enabled: true
        )

      edge_a_b =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: nil,
          source_job_id: job_a.id,
          target_job_id: job_b.id,
          condition_type: :on_job_success,
          enabled: true
        )

      workflow = %Lightning.Workflows.Workflow{
        id: Ecto.UUID.generate(),
        name: "round trip workflow",
        jobs: [job_a, job_b],
        triggers: [trigger],
        edges: [edge_t, edge_a_b]
      }

      %{workflow: workflow, jobs: [job_a, job_b], trigger: trigger}
    end

    test "emits v2 shape (steps array, hyphenated ids, no v1 keys)", %{
      workflow: workflow
    } do
      assert {:ok, yaml} = V2.serialize_workflow(workflow)

      assert yaml =~ "name: round trip workflow"
      assert yaml =~ ~r/^\s*steps:/m

      # Hyphenated step ids derived from job/trigger names.
      assert yaml =~ "- id: webhook"
      assert yaml =~ "- id: step-alpha"
      assert yaml =~ "- id: step-beta"

      # No v1 keys leak through.
      refute yaml =~ ~r/^\s*jobs:/m
      refute yaml =~ ~r/^\s*edges:/m
    end

    test "single :always edge collapses to plain string target", %{
      workflow: workflow
    } do
      {:ok, yaml} = V2.serialize_workflow(workflow)
      # webhook trigger -> step-alpha is the only :always edge
      assert yaml =~ "next: step-alpha"
    end

    test "non-:always edges emit condition as a JS expression", %{
      workflow: workflow
    } do
      {:ok, yaml} = V2.serialize_workflow(workflow)

      # step-alpha -> step-beta is :on_job_success → canonical JS "!state.errors"
      assert yaml =~ ~r/step-beta:\s*\n\s*condition: '!state\.errors'/
    end

    test "emits `expression:` (not `body:`) for step code", %{workflow: workflow} do
      {:ok, yaml} = V2.serialize_workflow(workflow)
      assert yaml =~ "expression: |"
      refute yaml =~ ~r/^\s*body:/m
    end

    test "emits flat `cron_expression:` on trigger and `cron_cursor:` under openfn" do
      cursor_job =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "cursor step",
          body: "fn(state => state)\n"
        )

      cron =
        build(:trigger,
          id: Ecto.UUID.generate(),
          type: :cron,
          enabled: true,
          cron_expression: "0 6 * * *",
          cron_cursor_job_id: cursor_job.id
        )

      edge =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: cron.id,
          source_job_id: nil,
          target_job_id: cursor_job.id,
          condition_type: :always,
          enabled: true
        )

      workflow = %Lightning.Workflows.Workflow{
        id: Ecto.UUID.generate(),
        name: "cron flow",
        jobs: [cursor_job],
        triggers: [cron],
        edges: [edge]
      }

      {:ok, yaml} = V2.serialize_workflow(workflow)

      # Spec: `cron_expression` is a flat field on the trigger, not under openfn.
      assert yaml =~ ~r/cron_expression: '0 6 \* \* \*'/
      # Lightning extension stays under openfn.
      assert yaml =~ ~r/openfn:\s*\n\s*cron_cursor: cursor-step/
      refute yaml =~ "cron_cursor_job"
    end

    test "kafka trigger emits a kafka: block with hosts joined as host:port" do
      consumer =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "consume",
          body: "fn(state => state)\n"
        )

      kafka_trigger =
        build(:trigger,
          id: Ecto.UUID.generate(),
          type: :kafka,
          enabled: true,
          kafka_configuration: %Lightning.Workflows.Triggers.KafkaConfiguration{
            hosts: [["localhost", "9092"]],
            topics: ["events"],
            initial_offset_reset_policy: "earliest",
            connect_timeout: 30
          }
        )

      edge =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: kafka_trigger.id,
          source_job_id: nil,
          target_job_id: consumer.id,
          condition_type: :always,
          enabled: true
        )

      workflow = %Lightning.Workflows.Workflow{
        id: Ecto.UUID.generate(),
        name: "kafka flow",
        jobs: [consumer],
        triggers: [kafka_trigger],
        edges: [edge]
      }

      {:ok, yaml} = V2.serialize_workflow(workflow)

      assert yaml =~ "kafka:"
      assert yaml =~ "'localhost:9092'"
      assert yaml =~ "topics:"
      refute yaml =~ "kafka_configuration"
    end

    test "js_expression edges emit the JS body inline as `condition`" do
      a =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "a",
          body: "fn(state => state)\n"
        )

      b =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "b",
          body: "fn(state => state)\n"
        )

      trigger =
        build(:trigger, id: Ecto.UUID.generate(), type: :webhook, enabled: true)

      edge_t =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: trigger.id,
          source_job_id: nil,
          target_job_id: a.id,
          condition_type: :always,
          enabled: true
        )

      js_edge =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: nil,
          source_job_id: a.id,
          target_job_id: b.id,
          condition_type: :js_expression,
          condition_expression: "state.go === true\n",
          condition_label: "go condition",
          enabled: true
        )

      workflow = %Lightning.Workflows.Workflow{
        id: Ecto.UUID.generate(),
        name: "js edge flow",
        jobs: [a, b],
        triggers: [trigger],
        edges: [edge_t, js_edge]
      }

      {:ok, yaml} = V2.serialize_workflow(workflow)

      # Per the portability spec, `condition` is the JS expression body.
      # Multi-line bodies emit as a `|` literal block.
      assert yaml =~ "condition: |"
      assert yaml =~ "state.go === true"
      assert yaml =~ "label: go condition"

      # No more discriminator literal or sibling `expression:` field.
      refute yaml =~ "condition: js_expression"
      refute yaml =~ ~r/^\s*expression: \|\s*\n\s*state\.go/m
      refute yaml =~ "condition_expression"
      refute yaml =~ "condition_type"
    end

    test "always edges emit no `condition:` key (spec: omit when unconditional)" do
      a =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "a",
          body: "fn(state => state)\n"
        )

      b =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "b",
          body: "fn(state => state)\n"
        )

      c =
        build(:job,
          id: Ecto.UUID.generate(),
          name: "c",
          body: "fn(state => state)\n"
        )

      trigger =
        build(:trigger, id: Ecto.UUID.generate(), type: :webhook, enabled: true)

      edge_t =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: trigger.id,
          source_job_id: nil,
          target_job_id: a.id,
          condition_type: :always,
          enabled: true
        )

      # Two outgoing :always edges from `a` (collapse-to-string blocked by
      # multi-target), forcing the object form.
      edge_a_b =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: nil,
          source_job_id: a.id,
          target_job_id: b.id,
          condition_type: :always,
          enabled: true
        )

      edge_a_c =
        build(:edge,
          id: Ecto.UUID.generate(),
          source_trigger_id: nil,
          source_job_id: a.id,
          target_job_id: c.id,
          condition_type: :always,
          enabled: true
        )

      workflow = %Lightning.Workflows.Workflow{
        id: Ecto.UUID.generate(),
        name: "always flow",
        jobs: [a, b, c],
        triggers: [trigger],
        edges: [edge_t, edge_a_b, edge_a_c]
      }

      {:ok, yaml} = V2.serialize_workflow(workflow)

      # Object form `b: {}` and `c: {}` for unconditional multi-target edges.
      assert yaml =~ "b: {}"
      assert yaml =~ "c: {}"
      refute yaml =~ "condition:"
    end
  end
end
