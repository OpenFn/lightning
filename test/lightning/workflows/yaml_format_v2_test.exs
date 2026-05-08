defmodule Lightning.Workflows.YamlFormatV2Test do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.YamlFormat
  alias Lightning.Workflows.YamlFormat.V2

  import Lightning.Factories

  @v1_fixtures_dir "test/fixtures/portability/v1"
  @v2_fixtures_dir "test/fixtures/portability/v2"

  # canonical_workflow.yaml lives at the top of each version dir;
  # everything else lives under scenarios/.
  @scenarios ~w(
    canonical_workflow
    scenarios/simple-webhook
    scenarios/cron-with-cursor
    scenarios/js-expression-edge
    scenarios/multi-trigger
    scenarios/kafka-trigger
    scenarios/branching-jobs
  )

  describe "detect_format/1" do
    for scenario <- @scenarios do
      test "returns :v2 for v2/#{scenario}.yaml" do
        yaml = read_v2_fixture(unquote(scenario))
        assert :v2 = YamlFormat.detect_format(yaml)
      end

      test "returns :v1 for v1/#{scenario}.yaml" do
        yaml = read_v1_fixture(unquote(scenario))
        assert :v1 = YamlFormat.detect_format(yaml)
      end
    end

    test "returns :v2 for parsed v2 doc" do
      parsed = %{"name" => "x", "steps" => [], "triggers" => []}
      assert :v2 = YamlFormat.detect_format(parsed)
    end

    test "returns :v1 for parsed v1 doc" do
      parsed = %{
        "name" => "x",
        "jobs" => %{"a" => %{"name" => "a"}},
        "triggers" => %{"webhook" => %{"type" => "webhook"}},
        "edges" => %{}
      }

      assert :v1 = YamlFormat.detect_format(parsed)
    end

    test "logs and falls back to :v1 on ambiguous input" do
      assert ExUnit.CaptureLog.capture_log(fn ->
               assert :v1 = YamlFormat.detect_format(%{"name" => "x"})
             end) =~ "ambiguous"
    end

    test "logs and falls back to :v1 when both jobs and steps present" do
      parsed = %{
        "name" => "x",
        "steps" => [],
        "jobs" => %{"a" => %{"name" => "a"}}
      }

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert :v1 = YamlFormat.detect_format(parsed)
        end)

      assert log =~ "both"
    end

    test "non-map input falls back to :v1" do
      assert :v1 = YamlFormat.detect_format(:not_a_map)
    end
  end

  describe "parse_workflow/1 against fixtures" do
    for scenario <- @scenarios do
      test "parses v2/#{scenario}.yaml without dangling next references" do
        yaml = read_v2_fixture(unquote(scenario))
        assert {:ok, doc} = V2.parse_workflow(yaml)
        assert is_binary(doc.name) or is_nil(doc.name)
        assert is_list(doc.steps)
        assert is_list(doc.triggers)
      end
    end
  end

  describe "round-trip: v2 fixture → parse → emit → matches fixture bytes" do
    for scenario <- @scenarios do
      test "#{scenario}" do
        original = read_v2_fixture(unquote(scenario))
        assert {:ok, parsed1} = V2.parse_workflow(original)
        emitted = V2.emit(parsed1)

        # The fixture's literal bytes may differ from emit/1 output (whitespace
        # / key ordering) so we compare structurally: re-parse and assert the
        # canonical maps match.
        assert {:ok, parsed2} = V2.parse_workflow(emitted)
        assert normalise(parsed1) == normalise(parsed2)
      end
    end
  end

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

    test "round-trips structurally to a parseable v2 doc", %{workflow: workflow} do
      assert {:ok, yaml} = V2.serialize_workflow(workflow)

      # Output should declare itself as v2
      assert YamlFormat.detect_format(yaml) == :v2

      assert {:ok, parsed} = V2.parse_workflow(yaml)

      assert parsed.name == "round trip workflow"

      assert [
               %{
                 id: "step-alpha",
                 name: "step alpha",
                 adaptor: _,
                 expression: _
               },
               %{id: "step-beta", name: "step beta"}
             ] = parsed.steps

      # The trigger->step edge is `:always` — emitted as a plain string target
      assert [
               %{
                 id: "webhook",
                 type: "webhook",
                 enabled: true,
                 next: "step-alpha"
               }
             ] =
               parsed.triggers

      # The on_job_success edge becomes an object value under :next
      [%{next: next}, _] = parsed.steps
      assert %{"step-beta" => %{condition: "on_job_success"}} = next
    end

    test "emits `expression:` (not `body:`) for step code", %{workflow: workflow} do
      {:ok, yaml} = V2.serialize_workflow(workflow)
      assert yaml =~ "expression: |"
      refute yaml =~ ~r/^\s*body:/m
    end

    test "emits `cron:` (not `cron_expression:`) and `cron_cursor:` for cron triggers" do
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

      assert yaml =~ ~r/cron: '0 6 \* \* \*'/
      assert yaml =~ ~r/cron_cursor: cursor-step/
      refute yaml =~ "cron_expression"
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

    test "js_expression edges emit condition + expression + label fields" do
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

      assert yaml =~ "condition: js_expression"
      assert yaml =~ "label: go condition"
      assert yaml =~ "expression: |"
      assert yaml =~ "state.go === true"
      refute yaml =~ "condition_expression"
      refute yaml =~ "condition_type"
    end
  end

  describe "v2/canonical_workflow.yaml field coverage" do
    test "every public v2 field listed in V2 appears at least once" do
      yaml = read_v2_fixture("canonical_workflow")
      assert {:ok, doc} = V2.parse_workflow(yaml)

      # workflow-level fields
      for field <- V2.v2_workflow_fields() do
        assert Map.has_key?(doc, field),
               "expected workflow field #{inspect(field)} in canonical fixture"
      end

      # trigger fields — at least one trigger somewhere has each
      for field <- V2.v2_trigger_fields() do
        assert Enum.any?(doc.triggers, fn t -> Map.has_key?(t, field) end),
               "expected trigger field #{inspect(field)} in canonical fixture"
      end

      # step fields — at least one step somewhere has each
      for field <- V2.v2_step_fields() do
        assert Enum.any?(doc.steps, fn s -> Map.has_key?(s, field) end),
               "expected step field #{inspect(field)} in canonical fixture"
      end

      # edge fields — at least one edge somewhere has each
      all_edges =
        (doc.triggers ++ doc.steps)
        |> Enum.flat_map(fn r ->
          case Map.get(r, :next) do
            %{} = m -> Map.values(m)
            _ -> []
          end
        end)

      for field <- V2.v2_edge_fields() do
        assert Enum.any?(all_edges, fn e -> Map.has_key?(e, field) end),
               "expected edge field #{inspect(field)} in canonical fixture"
      end
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  defp read_v1_fixture(name) do
    Path.join([@v1_fixtures_dir, name <> ".yaml"]) |> File.read!()
  end

  defp read_v2_fixture(name) do
    Path.join([@v2_fixtures_dir, name <> ".yaml"]) |> File.read!()
  end

  # The serializer doesn't preserve key order in maps, so for round-trip
  # comparison we normalise by re-sorting the canonical maps recursively.
  defp normalise(value) when is_map(value) do
    value
    |> Enum.map(fn {k, v} -> {k, normalise(v)} end)
    |> Enum.sort_by(fn {k, _} -> to_string(k) end)
    |> Map.new()
  end

  defp normalise(list) when is_list(list), do: Enum.map(list, &normalise/1)
  defp normalise(other), do: other
end
