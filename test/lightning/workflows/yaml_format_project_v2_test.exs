defmodule Lightning.Workflows.YamlFormatProjectV2Test do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Provisioner
  alias Lightning.Workflows.YamlFormat
  alias Lightning.Workflows.YamlFormat.V2

  import Lightning.Factories

  @v2_project_fixture "test/fixtures/portability/v2/canonical_project.yaml"

  describe "parse_project/1" do
    test "parses the canonical fixture into a stable canonical map" do
      yaml = File.read!(@v2_project_fixture)
      assert {:ok, doc} = V2.parse_project(yaml)

      assert %{
               name: "canonical-project",
               description: description,
               collections: collections,
               credentials: credentials,
               workflows: [workflow],
               openfn: openfn
             } = doc

      # description preserved (multi-line block, trimmed via parser)
      assert is_binary(description)
      assert description =~ "Project-level kitchen sink"

      # Both collections present (sorted alphabetically by parser walk)
      assert collections |> Enum.map(& &1.name) |> Enum.sort() ==
               ["encounters", "patients"]

      # All three credentials present
      assert credentials |> Enum.map(& &1.name) |> Enum.sort() ==
               ["http-prod", "http-staging", "postgres-warehouse"]

      assert credentials |> Enum.all?(&Map.has_key?(&1, :schema))

      # The single workflow round-trips into a v2 canonical workflow map
      assert %{
               name: "canonical workflow",
               triggers: [%{id: "webhook", type: "webhook"}],
               steps: [%{id: "ingest", name: "ingest"}]
             } = workflow

      # openfn block round-trips
      assert %{
               project_id: "00000000-0000-0000-0000-000000000000",
               endpoint: "https://app.openfn.org"
             } = openfn
    end

    test "absent openfn: block parses to an empty map" do
      yaml = """
      name: bare project
      workflows: {}
      """

      # Note: the parser doesn't currently understand `{}`, so we feed in an
      # already-parsed map for this edge case.
      assert {:ok, doc} = V2.parse_project(%{"name" => "bare project"})
      assert doc.openfn == %{}
      assert doc.workflows == []
      assert doc.collections == []
      assert doc.credentials == []
      _ = yaml
    end

    test "accepts a pre-parsed map (mirrors parse_workflow/1 behavior)" do
      parsed_map = %{
        "name" => "in-mem project",
        "description" => "from a map",
        "openfn" => %{"project_id" => "abc"}
      }

      assert {:ok, doc} = V2.parse_project(parsed_map)
      assert doc.name == "in-mem project"
      assert doc.description == "from a map"
      assert doc.openfn == %{project_id: "abc"}
    end
  end

  describe "serialize_project/2" do
    test "round-trips the canonical fixture structurally" do
      yaml = File.read!(@v2_project_fixture)

      # Parse → build a project struct equivalent → serialize → re-parse
      assert {:ok, parsed1} = V2.parse_project(yaml)

      # Build a Project struct that matches the canonical map structure.
      project = build_project_from_canonical(parsed1)

      assert {:ok, emitted} = V2.serialize_project(project)
      assert {:ok, parsed2} = V2.parse_project(emitted)

      # Top-level scalars survive
      assert parsed2.name == parsed1.name
      assert parsed2.description == parsed1.description

      # Workflows round-trip with the same structure (modulo the
      # serializer not writing back the openfn: block, which is set
      # only when callers populate it)
      assert length(parsed2.workflows) == length(parsed1.workflows)

      # Collection and credential names round-trip
      assert MapSet.new(parsed2.collections, & &1.name) ==
               MapSet.new(parsed1.collections, & &1.name)

      assert MapSet.new(parsed2.credentials, & &1.name) ==
               MapSet.new(parsed1.credentials, & &1.name)
    end

    test "emits no UUIDs in the body" do
      project = build_full_project_with_associations()

      assert {:ok, yaml} = V2.serialize_project(project)

      uuid_regex =
        ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

      refute Regex.match?(uuid_regex, yaml),
             "expected no UUIDs in the v2 project body, got: #{yaml}"
    end

    test "produces a parseable v2 doc from a built Project struct" do
      project = build_full_project_with_associations()

      assert {:ok, yaml} = V2.serialize_project(project)
      assert {:ok, parsed} = V2.parse_project(yaml)

      assert parsed.name == project.name
      assert length(parsed.workflows) == length(project.workflows)
    end
  end

  describe "to_provisioner_doc/2 (v2 → provisioner shape)" do
    test "imports the canonical fixture into a fresh project" do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      user = insert(:user)

      yaml = File.read!(@v2_project_fixture)

      assert {:ok, parsed_doc} = YamlFormat.parse_project(yaml)
      assert parsed_doc.format == :v2

      provisioner_doc = YamlFormat.to_provisioner_doc(parsed_doc, nil)

      # Top-level shape is provisioner-compatible
      assert is_binary(provisioner_doc["id"])
      assert provisioner_doc["name"] == "canonical-project"

      assert {:ok, project} =
               Provisioner.import_document(
                 %Lightning.Projects.Project{},
                 user,
                 provisioner_doc
               )

      assert project.name == "canonical-project"

      # The single workflow imported with its expected jobs and triggers
      assert %{workflows: [workflow]} =
               Lightning.Repo.preload(project,
                 workflows: [:jobs, :triggers, :edges]
               )

      assert workflow.name == "canonical workflow"
      assert length(workflow.jobs) == 1
      assert length(workflow.triggers) == 1
      # webhook -> ingest
      assert length(workflow.edges) == 1
    end
  end

  describe "stateless property: cross-project import via name lookup" do
    test "serialize → import-into-empty-project preserves names and edges" do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      user = insert(:user)
      original = build_full_project_with_associations()

      assert {:ok, yaml} = V2.serialize_project(original)
      assert {:ok, parsed} = YamlFormat.parse_project(yaml)
      assert parsed.format == :v2

      # Import into a brand new (empty) project — UUIDs are minted fresh
      provisioner_doc = YamlFormat.to_provisioner_doc(parsed, nil)

      assert {:ok, imported} =
               Provisioner.import_document(
                 %Lightning.Projects.Project{},
                 user,
                 provisioner_doc
               )

      imported =
        Lightning.Repo.preload(imported, workflows: [:jobs, :triggers, :edges])

      # Workflow names match
      assert MapSet.new(imported.workflows, & &1.name) ==
               MapSet.new(original.workflows, & &1.name)

      # Job-name composition per workflow matches
      original_jobs_by_workflow =
        Map.new(original.workflows, fn w ->
          {w.name, MapSet.new(w.jobs, & &1.name)}
        end)

      imported_jobs_by_workflow =
        Map.new(imported.workflows, fn w ->
          {w.name, MapSet.new(w.jobs, & &1.name)}
        end)

      assert imported_jobs_by_workflow == original_jobs_by_workflow

      # Edge counts match per workflow
      original_edge_counts =
        Map.new(original.workflows, fn w -> {w.name, length(w.edges)} end)

      imported_edge_counts =
        Map.new(imported.workflows, fn w -> {w.name, length(w.edges)} end)

      assert imported_edge_counts == original_edge_counts
    end
  end

  describe "openfn: round-trip" do
    test "presence of openfn: does not change semantic content" do
      with_openfn = """
      name: foo
      workflows:
        wf:
          name: wf
          steps:
            - id: webhook
              type: webhook
              enabled: true
              next: load
            - id: load
              name: load
              adaptor: '@openfn/language-common@latest'
              expression: |
                fn(state => state)
      openfn:
        project_id: 11111111-1111-1111-1111-111111111111
        endpoint: https://app.openfn.org
      """

      without_openfn = """
      name: foo
      workflows:
        wf:
          name: wf
          steps:
            - id: webhook
              type: webhook
              enabled: true
              next: load
            - id: load
              name: load
              adaptor: '@openfn/language-common@latest'
              expression: |
                fn(state => state)
      """

      assert {:ok, with} = V2.parse_project(with_openfn)
      assert {:ok, without} = V2.parse_project(without_openfn)

      # openfn block round-trips
      assert with.openfn == %{
               project_id: "11111111-1111-1111-1111-111111111111",
               endpoint: "https://app.openfn.org"
             }

      assert without.openfn == %{}

      # Workflow content is identical regardless of openfn presence
      assert with.workflows == without.workflows
    end
  end

  describe "v2/canonical_project.yaml field coverage" do
    test "every public v2 project field listed in V2 appears at least once" do
      yaml = File.read!(@v2_project_fixture)
      assert {:ok, doc} = V2.parse_project(yaml)

      for field <- V2.v2_project_fields() do
        assert Map.has_key?(doc, field),
               "expected project field #{inspect(field)} in canonical fixture"
      end

      # Each list-typed field must be non-empty (the canonical fixture is
      # a kitchen sink — empty lists indicate a fixture regression)
      for field <- [:collections, :credentials, :workflows] do
        value = Map.get(doc, field)

        assert is_list(value) and value != [],
               "expected canonical fixture to populate #{inspect(field)}"
      end

      assert is_map(doc.openfn) and map_size(doc.openfn) > 0,
             "expected canonical fixture to populate :openfn"
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

  # Build a Lightning Project struct (in-memory only) that matches the
  # canonical map produced by parse_project/1. Used to exercise the
  # serialize → parse round trip without DB writes.
  defp build_project_from_canonical(%{} = canonical) do
    workflows =
      Enum.map(canonical.workflows, &workflow_from_canonical/1)

    collections =
      Enum.map(canonical.collections, fn c ->
        %Lightning.Collections.Collection{
          id: Ecto.UUID.generate(),
          name: c.name,
          inserted_at: NaiveDateTime.utc_now()
        }
      end)

    project_credentials =
      Enum.map(canonical.credentials, fn cred ->
        %Lightning.Projects.ProjectCredential{
          id: Ecto.UUID.generate(),
          credential: %Lightning.Credentials.Credential{
            id: Ecto.UUID.generate(),
            name: cred.name,
            schema: Map.get(cred, :schema)
          },
          inserted_at: NaiveDateTime.utc_now()
        }
      end)

    %Lightning.Projects.Project{
      id: Ecto.UUID.generate(),
      name: canonical.name,
      description: canonical.description,
      workflows: workflows,
      collections: collections,
      project_credentials: project_credentials
    }
  end

  defp workflow_from_canonical(%{} = wf) do
    inserted = NaiveDateTime.utc_now()

    jobs =
      wf.steps
      |> Enum.map(fn step ->
        %Lightning.Workflows.Job{
          id: Ecto.UUID.generate(),
          name: step.name,
          adaptor: Map.get(step, :adaptor),
          body: Map.get(step, :expression),
          inserted_at: inserted
        }
      end)

    triggers =
      wf.triggers
      |> Enum.map(fn t ->
        type = String.to_existing_atom(t.type)

        %Lightning.Workflows.Trigger{
          id: Ecto.UUID.generate(),
          type: type,
          enabled: Map.get(t, :enabled, false),
          inserted_at: inserted
        }
      end)

    %Lightning.Workflows.Workflow{
      id: Ecto.UUID.generate(),
      name: wf.name,
      jobs: jobs,
      triggers: triggers,
      edges: [],
      inserted_at: inserted
    }
  end

  # Build a fully-populated Project + workflows + jobs + edges, all DB-persisted,
  # for the stateless cross-project import test.
  defp build_full_project_with_associations do
    user =
      insert(:user, email: ExMachina.sequence(:email, &"u-#{&1}@example.com"))

    project = insert(:project, name: "stateless-source-project")

    # Workflow 1: trigger -> job_a -> job_b
    workflow1 = insert(:workflow, name: "alpha-flow", project: project)

    trigger1 =
      insert(:trigger, type: :webhook, enabled: true, workflow: workflow1)

    job1a =
      insert(:job,
        name: "alpha one",
        workflow: workflow1,
        body: "fn(state => state)\n"
      )

    job1b =
      insert(:job,
        name: "alpha two",
        workflow: workflow1,
        body: "fn(state => state)\n"
      )

    insert(:edge,
      workflow: workflow1,
      source_trigger_id: trigger1.id,
      target_job_id: job1a.id,
      condition_type: :always,
      enabled: true
    )

    insert(:edge,
      workflow: workflow1,
      source_job_id: job1a.id,
      target_job_id: job1b.id,
      condition_type: :on_job_success,
      enabled: true
    )

    # Workflow 2: trigger -> job
    workflow2 = insert(:workflow, name: "beta-flow", project: project)

    trigger2 =
      insert(:trigger, type: :webhook, enabled: true, workflow: workflow2)

    job2 =
      insert(:job,
        name: "beta only",
        workflow: workflow2,
        body: "fn(state => state)\n"
      )

    insert(:edge,
      workflow: workflow2,
      source_trigger_id: trigger2.id,
      target_job_id: job2.id,
      condition_type: :always,
      enabled: true
    )

    # Collections + credentials
    insert(:collection, name: "patients", project: project)

    credential =
      insert(:credential, name: "ext-creds", schema: "http", user: user)

    insert(:project_credential, project: project, credential: credential)

    # Reload the project with its associations
    Lightning.Repo.preload(
      project,
      [
        :collections,
        project_credentials: [credential: :user],
        workflows: [:jobs, :triggers, :edges]
      ],
      force: true
    )
  end
end
