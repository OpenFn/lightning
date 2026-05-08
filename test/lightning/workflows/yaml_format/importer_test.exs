defmodule Lightning.Workflows.YamlFormat.ImporterTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Project
  alias Lightning.Workflows.YamlFormat.Importer

  import Lightning.Factories

  setup do
    # The importer can call into Provisioner.import_document/4 which
    # consults the usage limiter; stub it ok so tests focus on format
    # bridging, not entitlement.
    Mox.stub(
      Lightning.Extensions.MockUsageLimiter,
      :limit_action,
      fn _action, _context -> :ok end
    )

    :ok
  end

  describe "to_provisioner_doc/2" do
    test "passes legacy provisioner-shape JSON through untouched" do
      legacy = %{
        "id" => Ecto.UUID.generate(),
        "name" => "leg-project",
        "workflows" => [
          %{
            "id" => Ecto.UUID.generate(),
            "name" => "wf-1",
            "jobs" => [],
            "triggers" => [],
            "edges" => []
          }
        ]
      }

      assert {:ok, doc} = Importer.to_provisioner_doc(legacy, nil)
      assert doc == legacy
    end

    test "translates v2 canonical-shape JSON into provisioner shape with UUIDs" do
      v2_canonical = %{
        "name" => "v2-project",
        "workflows" => %{
          "wf" => %{
            "name" => "wf",
            "steps" => [
              %{"id" => "webhook", "type" => "webhook", "next" => "load"},
              %{
                "id" => "load",
                "name" => "load",
                "adaptor" => "@openfn/language-common@latest",
                "expression" => "fn(state => state)\n"
              }
            ]
          }
        }
      }

      assert {:ok, doc} = Importer.to_provisioner_doc(v2_canonical, nil)

      # Top-level project shape
      assert is_binary(doc["id"])
      assert doc["name"] == "v2-project"
      assert [%{"id" => wf_id, "name" => "wf"} = wf] = doc["workflows"]
      assert is_binary(wf_id)

      # Workflow has UUIDs at every level required by the provisioner
      assert [%{"id" => job_id, "name" => "load"}] = wf["jobs"]
      assert is_binary(job_id)

      assert [%{"id" => trig_id, "type" => "webhook"}] = wf["triggers"]
      assert is_binary(trig_id)

      assert [
               %{
                 "id" => edge_id,
                 "source_trigger_id" => ^trig_id,
                 "target_job_id" => ^job_id,
                 "condition_type" => "always"
               }
             ] = wf["edges"]

      assert is_binary(edge_id)
    end

    test "errors propagate from the underlying parser" do
      assert {:error, _} = Importer.to_provisioner_doc(:not_a_map_or_string, nil)
    end
  end

  describe "import_document/4 — v2 canonical doc end-to-end" do
    test "imports the v2 canonical project fixture into a fresh project" do
      yaml = File.read!("test/fixtures/portability/v2/canonical_project.yaml")

      user = insert(:user)

      assert {:ok, %Project{} = project} =
               Importer.import_document(%Project{}, user, yaml)

      assert project.name == "canonical-project"

      project =
        Lightning.Repo.preload(project, workflows: [:jobs, :triggers, :edges])

      assert [workflow] = project.workflows
      assert workflow.name == "canonical workflow"

      # Trigger + job + edge counts match the fixture's webhook → ingest shape
      assert [%{type: :webhook}] = workflow.triggers
      assert [%{name: "ingest"}] = workflow.jobs
      assert [%{condition_type: :always}] = workflow.edges
    end

    test "imports a legacy provisioner-shape JSON unchanged (regression path)" do
      project_id = Ecto.UUID.generate()
      workflow_id = Ecto.UUID.generate()
      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      legacy = %{
        "id" => project_id,
        "name" => "legacy-project",
        "workflows" => [
          %{
            "id" => workflow_id,
            "name" => "default",
            "jobs" => [
              %{
                "id" => job_id,
                "name" => "first-job",
                "adaptor" => "@openfn/language-common@latest",
                "body" => "fn(state => state)\n"
              }
            ],
            "triggers" => [
              %{"id" => trigger_id, "type" => "webhook", "enabled" => true}
            ],
            "edges" => [
              %{
                "id" => edge_id,
                "source_trigger_id" => trigger_id,
                "target_job_id" => job_id,
                "condition_type" => "always",
                "enabled" => true
              }
            ]
          }
        ]
      }

      user = insert(:user)

      assert {:ok, %Project{id: ^project_id} = project} =
               Importer.import_document(%Project{}, user, legacy)

      project =
        Lightning.Repo.preload(project, workflows: [:jobs, :triggers, :edges])

      assert [%{id: ^workflow_id, jobs: [%{id: ^job_id}]} = wf] =
               project.workflows

      assert [%{id: ^trigger_id, type: :webhook}] = wf.triggers
      assert [%{id: ^edge_id, condition_type: :always}] = wf.edges
    end
  end

  describe "v1 vs v2 equivalence: same workflow, two formats, identical records" do
    @v1_yaml """
    name: simple-equivalence
    workflows:
      flow-a:
        name: flow a
        jobs:
          do-a-thing:
            name: do a thing
            adaptor: '@openfn/language-common@latest'
            body: |
              fn(state => state)
        triggers:
          webhook:
            type: webhook
            enabled: true
        edges:
          webhook->do-a-thing:
            source_trigger: webhook
            target_job: do-a-thing
            condition_type: always
            enabled: true
    """

    @v2_yaml """
    name: simple-equivalence
    workflows:
      flow-a:
        name: flow a
        steps:
          - id: webhook
            type: webhook
            enabled: true
            next: do-a-thing
          - id: do-a-thing
            name: do a thing
            adaptor: '@openfn/language-common@latest'
            expression: |
              fn(state => state)
    """

    test "v2 import produces structurally identical records to the v1 equivalent" do
      # The v1 *YAML* parser does not exist server-side (legacy v1 imports
      # always come pre-parsed as provisioner-shape JSON), so we hand-build
      # the legacy JSON form of the same workflow here.
      project_id = Ecto.UUID.generate()
      workflow_id = Ecto.UUID.generate()
      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()
      edge_id = Ecto.UUID.generate()

      legacy_provisioner_json = %{
        "id" => project_id,
        "name" => "simple-equivalence",
        "workflows" => [
          %{
            "id" => workflow_id,
            "name" => "flow a",
            "jobs" => [
              %{
                "id" => job_id,
                "name" => "do a thing",
                "adaptor" => "@openfn/language-common@latest",
                "body" => "fn(state => state)\n"
              }
            ],
            "triggers" => [
              %{"id" => trigger_id, "type" => "webhook", "enabled" => true}
            ],
            "edges" => [
              %{
                "id" => edge_id,
                "source_trigger_id" => trigger_id,
                "target_job_id" => job_id,
                "condition_type" => "always",
                "enabled" => true
              }
            ]
          }
        ]
      }

      user_v1 = insert(:user)
      user_v2 = insert(:user)

      assert {:ok, v1_project} =
               Importer.import_document(
                 %Project{},
                 user_v1,
                 legacy_provisioner_json
               )

      assert {:ok, v2_project} =
               Importer.import_document(%Project{}, user_v2, @v2_yaml)

      # Confirm v2 docs are also recognised when handed in YAML form
      assert v2_project.name == "simple-equivalence"

      v1_loaded =
        Lightning.Repo.preload(v1_project, workflows: [:jobs, :triggers, :edges])

      v2_loaded =
        Lightning.Repo.preload(v2_project, workflows: [:jobs, :triggers, :edges])

      # Compare by stable structural fields, not UUIDs
      assert structural_shape(v1_loaded) == structural_shape(v2_loaded)

      _ = @v1_yaml
    end
  end

  # Reduce a project to a comparable, UUID-free shape — used by the
  # cross-format equivalence assertion.
  defp structural_shape(%Project{} = project) do
    %{
      name: project.name,
      workflows:
        project.workflows
        |> Enum.map(&workflow_shape/1)
        |> Enum.sort_by(& &1.name)
    }
  end

  defp workflow_shape(workflow) do
    job_id_to_name =
      Enum.into(workflow.jobs, %{}, fn j -> {j.id, j.name} end)

    trigger_id_to_type =
      Enum.into(workflow.triggers, %{}, fn t -> {t.id, t.type} end)

    %{
      name: workflow.name,
      jobs:
        workflow.jobs
        |> Enum.map(fn j ->
          %{name: j.name, adaptor: j.adaptor, body: j.body}
        end)
        |> Enum.sort_by(& &1.name),
      triggers:
        workflow.triggers
        |> Enum.map(fn t -> %{type: t.type, enabled: t.enabled} end)
        |> Enum.sort_by(&{&1.type, &1.enabled}),
      edges:
        workflow.edges
        |> Enum.map(fn e ->
          %{
            source:
              cond do
                e.source_trigger_id ->
                  {:trigger, Map.get(trigger_id_to_type, e.source_trigger_id)}

                e.source_job_id ->
                  {:job, Map.get(job_id_to_name, e.source_job_id)}

                true ->
                  :unknown
              end,
            target_job: Map.get(job_id_to_name, e.target_job_id),
            condition_type: e.condition_type,
            enabled: e.enabled
          }
        end)
        |> Enum.sort_by(&{&1.source, &1.target_job, &1.condition_type})
    }
  end
end
