# This module will be re-introduced in https://github.com/OpenFn/Lightning/issues/1143
#
# TODO(#4718): the "pull a project" assertions below compare `actual_yaml`
# against `test/fixtures/portability/v2/canonical_project.yaml`, but the
# Lightning export hasn't been re-emitted since the v2 cutover and the
# expected fixture and actual output don't yet line up byte-for-byte.
# Refresh the fixtures when the @openfn/cli integration is exercised next.
defmodule Lightning.CliDeployTest do
  use LightningWeb.ConnCase, async: false

  require Logger

  import Lightning.Factories
  import Lightning.CredentialsFixtures
  import Mox

  alias Lightning.Accounts

  @cli_path Application.app_dir(:lightning, "priv/openfn/bin/openfn")

  @required_env [
    {"OPENFN_ENDPOINT", nil},
    {"OPENFN_API_KEY", nil},
    {"NODE_OPTIONS", "--dns-result-order=ipv4first"}
  ]

  @moduletag tmp_dir: true, integration: true

  setup :set_mox_from_context
  setup :verify_on_exit!

  setup do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    Mox.stub_with(LightningMock, Lightning.API)
    Mox.stub_with(Lightning.Tesla.Mock, Tesla.Adapter.Hackney)

    Mox.stub_with(
      Lightning.Extensions.MockUsageLimiter,
      Lightning.Extensions.UsageLimiter
    )

    :ok
  end

  describe "The openfn CLI can be used to" do
    @describetag :integration
    setup %{tmp_dir: tmp_dir} do
      url = LightningWeb.Endpoint.url()
      user = insert(:user, role: :superuser)
      token = Accounts.generate_api_token(user)

      config = %{
        endpoint: url,
        apiKey: token,
        specPath: Path.join(tmp_dir, "testProjectSpec.yaml"),
        statePath: Path.join(tmp_dir, "testProjectState.json")
      }

      config_path = Path.join(tmp_dir, "testConfig.json")

      %{user: user, config: config, config_path: config_path}
    end

    test "pull a valid project from a Lightning server", %{
      user: user,
      config: config,
      config_path: config_path
    } do
      # write config
      File.write(config_path, Jason.encode!(config))

      project = Lightning.ProjectsFixtures.canonical_project_fixture()

      # Try to pull for a non project user
      {logs, _exit_code} =
        System.cmd(
          @cli_path,
          ["pull", project.id, "-c", config_path],
          env: @required_env
        )

      assert logs =~ "Failed to authorize request with endpoint"
      assert logs =~ "403 Forbidden"

      # state and spec files are not saved
      refute File.exists?(config.statePath)
      refute File.exists?(config.specPath)

      insert(:project_user, project: project, user: user, role: :admin)

      # Try to pull with a project user
      System.cmd(
        @cli_path,
        ["pull", project.id, "-c", config_path],
        env: @required_env
      )

      # Check result
      expected_state = expected_project_state(project)

      actual_state = config.statePath |> File.read!() |> Jason.decode!()

      # encoding and decoding in order to transform values like dates into string
      expected_state_for_comparison =
        expected_state
        |> Jason.encode!()
        |> Jason.decode!()

      assert actual_state == expected_state_for_comparison

      expected_yaml =
        File.read!("test/fixtures/portability/v2/canonical_project.yaml")

      actual_yaml = File.read!(config.specPath)

      assert actual_yaml == expected_yaml
    end

    test "deploy a new project to a Lightning server", %{
      user: user,
      config: config,
      config_path: config_path
    } do
      # there's no project
      assert [] == Lightning.Repo.all(Lightning.Projects.Project)

      # Lets use the canonical spec
      specPath =
        Path.expand("test/fixtures/portability/v1/canonical_project.yaml")

      config = %{config | specPath: specPath}
      File.write(config_path, Jason.encode!(config))

      # only a superuser can deploy a new project
      # lets update the user's role to a normal user
      user |> Ecto.Changeset.change(%{role: :user}) |> Lightning.Repo.update!()

      {logs, _} =
        System.cmd(
          @cli_path,
          ["deploy", "-c", config_path, "--no-confirm"],
          env: @required_env
        )

      assert logs =~ "Failed to authorize request with endpoint"
      assert logs =~ "403 Forbidden"
      # no project has been created
      assert [] == Lightning.Repo.all(Lightning.Projects.Project)

      # lets update the user's role to a superuser and use the canonical email
      user
      |> Lightning.Repo.reload()
      |> Ecto.Changeset.change(%{
        role: :superuser,
        email: "cannonical-user@lightning.com"
      })
      |> Lightning.Repo.update!()

      credential_fixture(user_id: user.id, name: "new credential")

      System.cmd(
        @cli_path,
        ["deploy", "-c", config_path, "--no-confirm"],
        env: @required_env
      )

      assert [project] =
               Lightning.Repo.all(Lightning.Projects.Project)
               |> Lightning.Repo.preload(workflows: [:jobs, :triggers, :edges])

      assert project.name == "a-test-project"
      assert project.description == "This is only a test\n"

      assert Enum.count(project.workflows) == 2

      # workflow 1
      workflow_1 = Enum.find(project.workflows, &(&1.name == "workflow 1"))
      [trigger] = workflow_1.triggers

      assert match?(
               %{type: :webhook, cron_expression: nil, enabled: true},
               trigger
             )

      assert Enum.count(workflow_1.jobs) == 3
      # webhook job
      edge_1 =
        Enum.find(workflow_1.edges, fn edge ->
          edge.source_trigger_id == trigger.id
        end)

      job_1 = Enum.find(workflow_1.jobs, &(&1.id == edge_1.target_job_id))

      assert match?(
               %{
                 name: "webhook job",
                 adaptor: "@openfn/language-common@latest",
                 body: "console.log('webhook job')\nfn(state => state)\n"
               },
               job_1
             )

      # workflow 2
      workflow_2 = Enum.find(project.workflows, &(&1.name == "workflow 2"))
      [trigger] = workflow_2.triggers

      assert match?(
               %{type: :cron, cron_expression: "0 23 * * *", enabled: true},
               trigger
             )

      assert Enum.count(workflow_2.jobs) == 2
      # cron job
      edge =
        Enum.find(workflow_2.edges, fn edge ->
          edge.source_trigger_id == trigger.id
        end)

      job = Enum.find(workflow_2.jobs, &(&1.id == edge.target_job_id))

      assert match?(
               %{
                 name: "some cronjob",
                 adaptor: "@openfn/language-common@latest",
                 body: "console.log('hello!');\n"
               },
               job
             )
    end

    test "pull exports webhook_reply and cron_cursor_job fields", %{
      user: user,
      config: config,
      config_path: config_path
    } do
      File.write(config_path, Jason.encode!(config))

      # Build a project with a webhook trigger (webhook_reply) and a cron
      # trigger with cron_cursor_job_id
      webhook_trigger =
        build(:trigger, type: :webhook, webhook_reply: :after_completion)

      reply_job = build(:job, name: "reply job", body: "fn(state => state)")

      webhook_workflow =
        build(:workflow, name: "webhook reply workflow", project: nil)
        |> with_trigger(webhook_trigger)
        |> with_job(reply_job)
        |> with_edge({webhook_trigger, reply_job}, condition_type: :always)

      # Build the job first so we have its id
      cursor_job = build(:job, name: "cursor job", body: "fn(state => state)")

      cron_trigger =
        build(:trigger,
          type: :cron,
          cron_expression: "0 6 * * *",
          cron_cursor_job_id: cursor_job.id
        )

      cron_workflow =
        build(:workflow, name: "cron cursor workflow", project: nil)
        |> with_trigger(cron_trigger)
        |> with_job(cursor_job)
        |> with_edge({cron_trigger, cursor_job}, condition_type: :always)

      project =
        insert(:project,
          name: "webhook-reply-and-cron-cursor-project",
          project_users: [%{user: user, role: :owner}],
          workflows: [webhook_workflow, cron_workflow]
        )

      System.cmd(
        @cli_path,
        ["pull", project.id, "-c", config_path],
        env: @required_env
      )

      expected_yaml =
        File.read!(
          "test/fixtures/portability/v2/webhook_reply_and_cron_cursor_project.yaml"
        )

      actual_yaml = File.read!(config.specPath)

      assert actual_yaml == expected_yaml
    end

    test "deploy updates to an existing project on a Lightning server", %{
      user: user,
      config: config,
      config_path: config_path
    } do
      %{workflows: [%{jobs: [job_to_update | _rest]} = workflow_1 | _]} =
        project = Lightning.ProjectsFixtures.canonical_project_fixture()

      insert(:project_user, project: project, user: user, role: :admin)
      # Lets Pull to get the intial state and spec
      File.write(config_path, Jason.encode!(config))

      System.cmd(
        @cli_path,
        ["pull", project.id, "-c", config_path],
        env: @required_env
      )

      # Lets use the updated spec
      specPath =
        Path.expand("test/fixtures/portability/v1/canonical_update_project.yaml")

      config = %{config | specPath: specPath}
      File.write(config_path, Jason.encode!(config))

      assert project.description == "This is only a test"
      assert workflow_1.name == "workflow 1"
      assert job_to_update.name == "webhook job"

      assert job_to_update.body ==
               "console.log('webhook job')\nfn(state => state)"

      System.cmd(
        @cli_path,
        ["deploy", project.id, "-c", config_path, "--no-confirm"],
        env: @required_env
      )

      updated_project = Lightning.Repo.reload(project)
      assert updated_project.description == "This is an update"
      updated_workflow_1 = Lightning.Repo.reload(workflow_1)
      assert updated_workflow_1.id == workflow_1.id
      assert updated_workflow_1.name == "updated workflow 1"

      updated_job = Lightning.Repo.reload(job_to_update)
      assert updated_job.id == job_to_update.id
      assert updated_job.name == "updated webhook job"

      assert updated_job.body ==
               "console.log('updated webhook job')\nfn(state => state)\n"
    end

    test "round-trip: a v2 YAML pulled from Lightning re-deploys cleanly into a fresh project",
         %{
           user: user,
           config: config,
           config_path: config_path,
           tmp_dir: tmp_dir
         } do
      # Round-trip test: write a project in the DB, pull it as v2 YAML, then
      # use @openfn/project (the CLI's library) to parse the v2 YAML and
      # re-POST as JSON state. Asserts the cross-language round-trip:
      #   v2 YAML emit (Lightning) → @openfn/project parse → provisioner JSON
      #   → /api/provision POST → fresh records structurally equivalent.
      #
      # We build a small bespoke project (rather than the canonical fixture)
      # to avoid having to mint extra users — `canonical_project_fixture/0`
      # inserts its own owner with the email we'd otherwise need to
      # impersonate to claim deploy authority.
      user
      |> Ecto.Changeset.change(%{role: :superuser})
      |> Lightning.Repo.update!()

      trigger = build(:trigger, type: :webhook, enabled: true)

      job_a =
        build(:job,
          name: "alpha",
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)"
        )

      job_b =
        build(:job,
          name: "beta",
          adaptor: "@openfn/language-common@latest",
          body: "fn(state => state)"
        )

      workflow =
        build(:workflow, name: "rt-workflow", project: nil)
        |> with_trigger(trigger)
        |> with_job(job_a)
        |> with_job(job_b)
        |> with_edge({trigger, job_a}, condition_type: :always)
        |> with_edge({job_a, job_b}, condition_type: :on_job_success)

      source =
        insert(:project,
          name: "rt-source-project",
          project_users: [%{user: user, role: :owner}],
          workflows: [workflow]
        )

      File.write(config_path, Jason.encode!(config))

      # 1. Pull → writes v2 YAML to config.specPath. The CLI's post-pull
      # validator still expects the v1 wire shape (a known limitation) so
      # exit code is non-zero, but the YAML is written to disk before
      # validation runs. Same pattern as the existing 4 pull tests.
      System.cmd(
        @cli_path,
        ["pull", source.id, "-c", config_path],
        env: @required_env
      )

      assert File.exists?(config.specPath)

      # 2. Embed a Node script that uses @openfn/project to parse the v2
      #    YAML and POST the resulting state to /api/provision. The
      #    @openfn/project library (the same one the CLI's `--beta` deploy
      #    uses) treats `cli.version: 2` as the v2 marker; Lightning's V2
      #    emit doesn't include that field today, so we inject it before
      #    parsing. The library then translates the verbose `next:` map +
      #    `condition: <literal>` form into the legacy provisioner-shape
      #    JSON the unchanged `Provisioner.import_document/4` accepts.
      project_lib =
        Path.expand(
          "priv/openfn/lib/node_modules/@openfn/cli/node_modules/@openfn/project/dist/index.js"
        )

      script_path = Path.join(tmp_dir, "round_trip.mjs")
      result_path = Path.join(tmp_dir, "round_trip_result.json")

      File.write!(script_path, """
      import Project from '#{project_lib}';
      import { readFile, writeFile } from 'fs/promises';

      const [,, yamlPath, endpoint, apiKey, freshName, resultPath] = process.argv;

      let yaml = await readFile(yamlPath, 'utf8');
      if (!yaml.includes('cli:') && !/^version:/m.test(yaml)) {
        yaml = 'cli:\\n  version: 2\\n' + yaml;
      }

      const project = await Project.from('project', yaml);
      const state = project.serialize('state', { format: 'json' });

      // `serialize('state')` mints a fresh project UUID + nested record
      // UUIDs from the YAML's stable names. Keep the new id (so this lands
      // as a brand-new project record) and rename it so we can find it.
      state.name = freshName;

      const res = await fetch(endpoint + '/api/provision', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: 'Bearer ' + apiKey
        },
        body: JSON.stringify(state)
      });

      const body = await res.text();
      await writeFile(resultPath, JSON.stringify({ status: res.status, body }));
      if (!res.ok) process.exit(1);
      """)

      api_token = Accounts.generate_api_token(user)
      endpoint_url = LightningWeb.Endpoint.url()

      System.cmd(
        "node",
        [
          script_path,
          config.specPath,
          endpoint_url,
          api_token,
          "round-tripped",
          result_path
        ],
        env: [{"NODE_OPTIONS", "--dns-result-order=ipv4first"}]
      )

      result = result_path |> File.read!() |> Jason.decode!()
      assert result["status"] == 201, "deploy failed: #{result["body"]}"

      # 3. Verify a fresh project landed with structurally equivalent records.
      [_source, deployed] =
        Lightning.Repo.all(Lightning.Projects.Project)
        |> Lightning.Repo.preload(workflows: [:jobs, :triggers, :edges])
        |> Enum.sort_by(& &1.inserted_at, NaiveDateTime)

      assert deployed.name == "round-tripped"

      source =
        Lightning.Repo.preload(source, workflows: [:jobs, :triggers, :edges])

      assert workflow_summary(source) == workflow_summary(deployed)
    end
  end

  defp workflow_summary(%{workflows: workflows}) do
    workflows
    |> Enum.map(fn w ->
      %{
        name: w.name,
        jobs:
          w.jobs
          |> Enum.map(fn j ->
            # Trailing newline differs by an artifact of YAML block-literal
            # round-tripping; the body content is what matters.
            {j.name, j.adaptor, String.trim_trailing(j.body, "\n")}
          end)
          |> Enum.sort(),
        triggers:
          w.triggers
          |> Enum.map(fn t -> {t.type, t.enabled, t.cron_expression} end)
          |> Enum.sort(),
        edges:
          w.edges
          |> Enum.map(fn e ->
            {e.source_trigger_id != nil, e.condition_type, e.enabled}
          end)
          |> Enum.sort()
      }
    end)
    |> Enum.sort_by(& &1.name)
  end

  defp hyphenize(val) do
    String.replace(val, " ", "-")
  end

  defp expected_project_state(project) do
    state = Map.take(project, Lightning.Projects.Project.__schema__(:fields))

    workflows =
      Map.new(project.workflows, fn workflow ->
        {hyphenize(workflow.name), expected_workflow_state(workflow)}
      end)

    credentials =
      Map.new(project.project_credentials, fn pc ->
        {hyphenize("#{pc.credential.user.email} #{pc.credential.name}"),
         expected_project_credential_state(pc)}
      end)

    collections =
      Map.new(project.collections, fn collection ->
        {hyphenize(collection.name), expected_collection_state(collection)}
      end)

    Map.merge(state, %{
      workflows: workflows,
      project_credentials: credentials,
      collections: collections
    })
  end

  defp expected_collection_state(collection) do
    Map.take(collection, [:id, :name])
  end

  defp expected_project_credential_state(project_credential) do
    %{
      id: project_credential.id,
      name: project_credential.credential.name,
      owner: project_credential.credential.user.email
    }
  end

  defp expected_workflow_state(workflow) do
    state =
      workflow
      |> Map.take([
        :id,
        :name,
        :inserted_at,
        :updated_at,
        :deleted_at,
        :lock_version,
        :concurrency
      ])

    jobs =
      Map.new(workflow.jobs, fn job ->
        {hyphenize(job.name), expected_job_state(job)}
      end)

    triggers =
      Map.new(workflow.triggers, fn trigger ->
        {trigger.type, expected_trigger_state(trigger)}
      end)

    edges =
      Map.new(workflow.edges, fn edge ->
        source_key =
          if edge.source_trigger_id do
            source =
              Enum.find(workflow.triggers, &(&1.id == edge.source_trigger_id))

            source.type
          else
            source = Enum.find(workflow.jobs, &(&1.id == edge.source_job_id))
            source.name
          end

        target_job = Enum.find(workflow.jobs, &(&1.id == edge.target_job_id))

        key = hyphenize("#{source_key}->#{target_job.name}")

        {key, expected_edge_state(edge)}
      end)

    version_history = Lightning.WorkflowVersions.history_for(workflow)

    Map.merge(state, %{
      jobs: jobs,
      triggers: triggers,
      edges: edges,
      version_history: version_history
    })
  end

  defp expected_trigger_state(trigger) do
    trigger
    |> Map.take([
      :id,
      :type,
      :enabled,
      :cron_expression,
      :webhook_reply,
      :cron_cursor_job_id
    ])
    |> Map.reject(fn {_key, val} -> is_nil(val) end)
  end

  defp expected_job_state(job) do
    Map.take(job, [:id, :name, :body, :adaptor, :project_credential_id])
  end

  defp expected_edge_state(edge) do
    edge
    |> Map.take([
      :id,
      :enabled,
      :condition_type,
      :source_job_id,
      :source_trigger_id,
      :target_job_id
    ])
    |> Map.reject(fn {_key, val} -> is_nil(val) end)
  end
end
