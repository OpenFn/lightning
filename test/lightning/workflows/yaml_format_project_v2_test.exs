defmodule Lightning.Workflows.YamlFormatProjectV2Test do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.YamlFormat.V2

  import Lightning.Factories

  describe "serialize_project/2" do
    test "emits no UUIDs in the body" do
      project = build_full_project_with_associations()

      assert {:ok, yaml} = V2.serialize_project(project)

      uuid_regex =
        ~r/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/

      refute Regex.match?(uuid_regex, yaml),
             "expected no UUIDs in the v2 project body, got: #{yaml}"
    end

    test "emits a v2 project doc with id, workflows array and v2 step shape" do
      project = build_full_project_with_associations()

      assert {:ok, yaml} = V2.serialize_project(project)

      # Top-level project metadata: id (hyphenated) + name.
      assert yaml =~ "id: stateless-source-project"
      assert yaml =~ "name: stateless-source-project"

      # Spec: `workflows: WorkflowSpec[]` — emitted as a YAML sequence.
      # Each workflow item is `- id: <hyphenated>` followed by `name:` and
      # `steps:` continuation lines.
      assert yaml =~ ~r/^workflows:/m
      assert yaml =~ ~r/^\s*- id: alpha-flow/m
      assert yaml =~ ~r/^\s*- id: beta-flow/m

      # Each workflow body holds a `steps:` array (not v1 jobs/edges).
      assert yaml =~ ~r/^\s*steps:/m
      refute yaml =~ ~r/^\s*jobs:/m
      refute yaml =~ ~r/^\s*edges:/m

      # Trigger steps carry a `type:` discriminator (Lightning extension).
      assert yaml =~ "type: webhook"

      # Step ids are hyphenated names.
      assert yaml =~ "id: alpha-one"
      assert yaml =~ "id: alpha-two"
      assert yaml =~ "id: beta-only"

      # Edge condition surfaces as the literal for the named on_job_success
      # edge (per lightning.d.ts:102 the spec accepts the literal alongside
      # JS bodies; we emit the literal).
      assert yaml =~ "condition: on_job_success"

      # Spec: `collections: string[]` — sequence of names.
      assert yaml =~ ~r/^collections:\s*\n\s*- patients/m

      # Spec: `credentials: Credential[]` (`{name, owner}`).
      assert yaml =~ ~r/^\s*- name: ext-creds/m
      assert yaml =~ ~r/owner: u-\d+@example\.com/
    end
  end

  # ── helpers ────────────────────────────────────────────────────────────────

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
