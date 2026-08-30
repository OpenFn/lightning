defmodule Lightning.ExportUtilsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.ExportUtils
  alias Lightning.Projects

  @fixture "test/fixtures/unicode_project.yaml"

  # The names below are the ones YAML gets wrong if we concatenate strings
  # without quoting: an apostrophe closes a single quoted scalar, `off` and a
  # bare date come back as a boolean and a date, and accented or CJK text falls
  # outside the character class the export used to test against.
  @workflow_one "Flujo 1: Registro en PS y gestión de perfiles"
  @workflow_two "off"
  @workflow_three "MailChimp June'24"

  @job_one "Vérifier l'état"
  @job_two "患者確認"
  @job_three "2026-08-27"
  @job_four "step 🎉"
  @job_five "a"

  @condition_label "évaluation \"rechazada\", ou pas"

  describe "generate_new_yaml/2 with names that need quoting" do
    setup do
      %{project: unicode_project()}
    end

    test "matches the committed fixture byte for byte", %{project: project} do
      {:ok, generated} = Projects.export_project(:yaml, project.id)

      assert generated == File.read!(@fixture) |> String.trim()
    end

    test "the exported spec parses back to the names it came from", %{
      project: project
    } do
      {:ok, generated} = Projects.export_project(:yaml, project.id)

      assert {:ok, parsed} = YamlElixir.read_from_string(generated)

      assert parsed["name"] == "unicode-export-test"

      workflows = parsed["workflows"]

      assert Enum.sort(Map.keys(workflows)) ==
               Enum.sort([
                 "Flujo-1:-Registro-en-PS-y-gestión-de-perfiles",
                 "off",
                 "MailChimp-June'24"
               ])

      workflow_one =
        workflows["Flujo-1:-Registro-en-PS-y-gestión-de-perfiles"]

      assert workflow_one["name"] == @workflow_one

      assert Enum.sort(Map.keys(workflow_one["jobs"])) ==
               Enum.sort(["Vérifier-l'état", "患者確認"])

      assert workflow_one["jobs"]["Vérifier-l'état"]["name"] == @job_one

      assert workflows["off"]["name"] == @workflow_two
      assert workflows["MailChimp-June'24"]["name"] == @workflow_three

      assert workflows["off"]["jobs"][@job_three]["name"] == @job_three

      [edge] =
        workflows["MailChimp-June'24"]["edges"]
        |> Map.values()
        |> Enum.filter(&(&1["condition_type"] == "js_expression"))

      assert edge["condition_label"] == @condition_label

      assert parsed["credentials"][
               "unicode-user@lightning.com-MailChimp-June'24"
             ]["name"] == "MailChimp June'24"

      assert parsed["collections"]["off"]["name"] == "off"

      assert parsed["channels"]["Flujo-1:-Registro"]["name"] ==
               "Flujo 1: Registro"
    end
  end

  describe "generate_new_yaml/2 for adaptor and cron_expression" do
    # These two used to be concatenated straight into the spec as
    # "\#{k}: '\#{v}'", the last unescaped concatenation in the module. They go
    # through Scalar.encode_quoted_value/1 now, which escapes but never leaves
    # the value bare, so the output is byte for byte what it always was.
    test "an adaptor is single-quoted" do
      project = cron_project("0 23 * * *")

      {:ok, generated} = Projects.export_project(:yaml, project.id)

      assert generated =~ "adaptor: '@openfn/language-common@latest'"
    end

    test "every cron shape is single-quoted, wildcard or not" do
      # `5 4 1 1 1` is 04:05 on 1 January when it falls on a Monday. It is the
      # one real value here that the bare-scalar regex would accept, so it is
      # the one that proves the forced quote is doing something.
      for cron <- [
            "0 23 * * *",
            "*/5 * * * *",
            "0 0 1 * *",
            "5 4 1 1 1",
            "0 0 1 1 1",
            "30 8 15 6 3"
          ] do
        project = cron_project(cron)

        {:ok, generated} = Projects.export_project(:yaml, project.id)

        assert generated =~ "cron_expression: '#{cron}'",
               "expected #{inspect(cron)} to be single-quoted"

        assert {:ok, parsed} = YamlElixir.read_from_string(generated)

        assert parsed["workflows"]["cron-workflow"]["triggers"]["cron"][
                 "cron_expression"
               ] == cron
      end
    end
  end

  describe "generate_new_yaml/2 key collisions" do
    test "two jobs that hyphenate to the same key are refused, naming both" do
      # Unreachable for a live workflow: jobs_name_workflow_id_index is unique
      # on LOWER(REPLACE(name, '-', ' ')), so the database already refuses `a b`
      # alongside `a-b`. Snapshot jobs live in a jsonb column with no such
      # index, so the guard still has to be here, and build_yaml_tree/2 is
      # called directly to reach it.
      # Built rather than inserted, so inserted_at has to be a NaiveDateTime
      # already; Ecto would have cast it on the way in.
      trigger = build(:trigger, type: :webhook, enabled: true)
      job_one = build(:job, name: "a b", inserted_at: naive_at(0))
      job_two = build(:job, name: "a-b", inserted_at: naive_at(1))

      workflow =
        build(:workflow, name: "collide", project: nil)
        |> with_trigger(trigger)
        |> with_job(job_one)
        |> with_job(job_two)

      project = %Lightning.Projects.Project{
        name: "job-key-collision",
        project_credentials: [],
        collections: [],
        channels: []
      }

      error =
        assert_raise Lightning.ExportUtils.DuplicateKeyError, fn ->
          ExportUtils.build_yaml_tree([workflow], project)
        end

      message = Exception.message(error)

      assert message =~ ~s("a-b")
      assert message =~ ~s("a b")
      assert message =~ "job in collide"
      assert message =~ "Rename one of them"
    end

    test "two workflows that hyphenate to the same key are refused" do
      # This used to be a silent Map.put overwrite: the project exported
      # cleanly and came back with one workflow instead of two.
      project =
        insert(:project,
          name: "workflow-key-collision",
          workflows: [
            simple_workflow_named("a b", 0),
            simple_workflow_named("a-b", 1)
          ]
        )

      assert {:error, message} = Projects.export_project(:yaml, project.id)

      assert message =~ "two workflows in this project"
      assert message =~ ~s("a-b")
      assert message =~ ~s("a b")
    end

    test "colliding edge keys are disambiguated rather than refused" do
      # Jobs `a`, `b->c`, `a->b` and `c` give two edges that both want the key
      # `a->b->c`. npm yaml hard-errors on a duplicate key and PyYAML keeps the
      # last, dropping an edge and changing control flow.
      trigger = build(:trigger, type: :webhook, enabled: true)
      job_a = build(:job, name: "a", inserted_at: at(0))
      job_bc = build(:job, name: "b->c", inserted_at: at(1))
      job_ab = build(:job, name: "a->b", inserted_at: at(2))
      job_c = build(:job, name: "c", inserted_at: at(3))

      workflow =
        build(:workflow, name: "edge-collision", project: nil)
        |> with_trigger(trigger)
        |> with_job(job_a)
        |> with_job(job_bc)
        |> with_job(job_ab)
        |> with_job(job_c)
        |> with_edge({trigger, job_a}, condition_type: :always)
        |> with_edge({job_a, job_bc}, condition_type: :on_job_success)
        |> with_edge({job_ab, job_c}, condition_type: :on_job_success)

      project =
        insert(:project, name: "edge-key-collision", workflows: [workflow])

      assert {:ok, generated} = Projects.export_project(:yaml, project.id)

      assert {:ok, parsed} = YamlElixir.read_from_string(generated)

      edges = parsed["workflows"]["edge-collision"]["edges"]

      # Both edges survive, under distinct keys, and each still names its own
      # source and target in the body, which is what the CLI reads.
      assert Enum.sort(Map.keys(edges)) == [
               "a->b->c",
               "a->b->c-2",
               "webhook->a"
             ]

      pairs =
        edges
        |> Map.values()
        |> Enum.reject(&Map.has_key?(&1, "source_trigger"))
        |> Enum.map(&{&1["source_job"], &1["target_job"]})
        |> Enum.sort()

      assert pairs == [{"a", "b->c"}, {"a->b", "c"}]
    end
  end

  defp simple_workflow_named(name, offset) do
    trigger = build(:trigger, type: :webhook, enabled: true)
    job = build(:job, name: "step", inserted_at: at(offset))

    build(:workflow, name: name, project: nil)
    |> with_trigger(trigger)
    |> with_job(job)
    |> with_edge({trigger, job}, condition_type: :always)
  end

  defp cron_project(cron_expression) do
    trigger =
      build(:trigger,
        type: :cron,
        cron_expression: cron_expression,
        enabled: true
      )

    job =
      build(:job,
        name: "step",
        adaptor: "@openfn/language-common@latest",
        inserted_at: at(0)
      )

    workflow =
      build(:workflow, name: "cron workflow", project: nil)
      |> with_trigger(trigger)
      |> with_job(job)
      |> with_edge({trigger, job}, condition_type: :always)

    insert(:project,
      name: "cron-export-test-#{System.unique_integer([:positive])}",
      workflows: [workflow]
    )
  end

  defp unicode_project do
    user = insert(:user, email: "unicode-user@lightning.com")

    credential =
      insert(:credential,
        user: user,
        name: "MailChimp June'24",
        body: %{"foo" => "bar"}
      )

    project_credential =
      build(:project_credential,
        id: Ecto.UUID.generate(),
        credential: credential,
        project: nil
      )

    workflow_one = workflow_one(project_credential)
    workflow_two = workflow_two()
    workflow_three = workflow_three()

    collection = build(:collection, name: "off", project: nil)

    channel =
      build(:channel,
        name: "Flujo 1: Registro",
        destination_url: "http://localhost",
        enabled: true,
        project: nil,
        destination_auth_method:
          build(:channel_auth_method,
            role: :destination,
            webhook_auth_method: nil,
            project_credential_id: project_credential.id
          )
      )

    insert(:project,
      name: "unicode-export-test",
      description: "Names that YAML would otherwise mangle",
      collections: [collection],
      channels: [channel],
      project_credentials: [project_credential],
      workflows: [workflow_one, workflow_two, workflow_three],
      project_users: [%{user: user}]
    )
  end

  defp workflow_one(project_credential) do
    trigger = build(:trigger, type: :webhook, enabled: true)

    job_one =
      build(:job,
        name: @job_one,
        inserted_at: at(0),
        body: "fn(state => state)",
        project_credential_id: project_credential.id
      )

    job_two = build(:job, name: @job_two, inserted_at: at(1))

    build(:workflow, name: @workflow_one, project: nil)
    |> with_trigger(trigger)
    |> with_job(job_one)
    |> with_job(job_two)
    |> with_edge({trigger, job_one}, condition_type: :always)
    |> with_edge({job_one, job_two}, condition_type: :on_job_success)
  end

  defp workflow_two do
    trigger =
      build(:trigger, type: :cron, cron_expression: "0 23 * * *", enabled: true)

    job_one = build(:job, name: @job_three, inserted_at: at(2))
    job_two = build(:job, name: @job_four, inserted_at: at(3))

    build(:workflow, name: @workflow_two, project: nil)
    |> with_trigger(trigger)
    |> with_job(job_one)
    |> with_job(job_two)
    |> with_edge({trigger, job_one}, condition_type: :always)
    |> with_edge({job_one, job_two}, condition_type: :on_job_failure)
  end

  defp workflow_three do
    trigger = build(:trigger, type: :webhook, enabled: true)

    job_one = build(:job, name: @job_five, inserted_at: at(4))

    job_two =
      build(:job, name: "trailing space ", inserted_at: at(5))

    build(:workflow, name: @workflow_three, project: nil)
    |> with_trigger(trigger)
    |> with_job(job_one)
    |> with_job(job_two)
    |> with_edge({trigger, job_one}, condition_type: :always)
    |> with_edge({job_one, job_two},
      condition_type: :js_expression,
      condition_label: @condition_label,
      condition_expression: "state.data.ok === true"
    )
  end

  defp at(seconds) do
    DateTime.utc_now() |> DateTime.add(seconds, :second)
  end

  defp naive_at(seconds) do
    NaiveDateTime.utc_now() |> NaiveDateTime.add(seconds, :second)
  end

  describe "hyphenate/1 parity with the client" do
    # ExportUtils.hyphenate/1 replaces each single space and leaves every other
    # whitespace character alone. The JS half pins this in
    # assets/test/yaml/util.test.ts; this side had nothing, so widening the
    # server back to ~r/\s+/ left the whole Elixir suite green while the two
    # ends silently disagreed about what a job's key is.
    test "two spaces give two hyphens, and other whitespace is left alone" do
      trigger = build(:trigger, type: :webhook, enabled: true)

      jobs = [
        {"a  b", "a--b"},
        {"one two", "one-two"},
        {"trailing ", "trailing-"},
        {"tab\tsep", "tab\tsep"},
        {"nbsp\u{00A0}sep", "nbsp\u{00A0}sep"}
      ]

      workflow =
        Enum.reduce(
          Enum.with_index(jobs),
          build(:workflow, name: "hyphenate", project: nil),
          fn
            {{name, _key}, i}, acc ->
              with_job(acc, build(:job, name: name, inserted_at: at(i)))
          end
        )
        |> with_trigger(trigger)

      project =
        insert(:project, name: "hyphenate-parity", workflows: [workflow])

      assert {:ok, generated} = Projects.export_project(:yaml, project.id)
      assert {:ok, parsed} = YamlElixir.read_from_string(generated)

      keys =
        parsed["workflows"]["hyphenate"]["jobs"] |> Map.keys() |> Enum.sort()

      assert keys == jobs |> Enum.map(&elem(&1, 1)) |> Enum.sort()

      # And the key really is the hyphenated name, which is the invariant the
      # CLI matches on.
      for {name, key} <- jobs do
        assert parsed["workflows"]["hyphenate"]["jobs"][key]["name"] == name
      end
    end
  end

  describe "the edge key disambiguation fixture" do
    # test/fixtures/edge_key_disambiguation.json is the one corpus both sides
    # see. This half pins the server; assets/test/yaml/edgeKeys.test.ts asserts
    # the browser produces the same keys. Only the JS half read it at first,
    # which let the server drift and the fixture go stale in silence.
    @edge_fixture "test/fixtures/edge_key_disambiguation.json"

    test "the server still produces exactly the keys in it" do
      for %{"label" => label, "jobs" => jobs, "edges" => pairs, "keys" => keys} <-
            @edge_fixture |> File.read!() |> Jason.decode!() do
        assert edge_keys_for(jobs, pairs) == keys, "#{label} drifted"
      end
    end

    test "a suffix is checked against the original keys, not just the used ones" do
      # Jobs `a`, `b` and `b-2` with edges (a,b), (a,b) and (a,b-2). The second
      # (a,b) cannot take `a->b-2`, because the third edge already owns it.
      keys =
        edge_keys_for(["a", "b", "b-2"], [["a", "b"], ["a", "b"], ["a", "b-2"]])

      assert keys == ["a->b", "a->b-3", "a->b-2"]
    end
  end

  defp edge_keys_for(job_names, pairs) do
    at = fn n -> NaiveDateTime.add(~N[2026-01-01 00:00:00], n, :second) end

    jobs =
      job_names
      |> Enum.with_index()
      |> Enum.map(fn {name, i} ->
        %Lightning.Workflows.Job{
          id: Ecto.UUID.generate(),
          name: name,
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)",
          inserted_at: at.(i)
        }
      end)

    by_name = Map.new(jobs, &{&1.name, &1})

    edges =
      pairs
      |> Enum.with_index()
      |> Enum.map(fn {[source, target], i} ->
        %Lightning.Workflows.Edge{
          id: Ecto.UUID.generate(),
          source_job_id: by_name[source].id,
          target_job_id: by_name[target].id,
          condition_type: :on_job_success,
          enabled: true,
          inserted_at: at.(i)
        }
      end)

    workflow = %Lightning.Workflows.Workflow{
      name: "w",
      jobs: jobs,
      triggers: [],
      edges: edges
    }

    project = %Lightning.Projects.Project{
      name: "p",
      project_credentials: [],
      collections: [],
      channels: []
    }

    [workflow]
    |> ExportUtils.build_yaml_tree(project)
    |> get_in([:workflows, "w"])
    |> Map.fetch!(:edges)
    |> Enum.map(& &1.name)
  end
end
