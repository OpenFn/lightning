defmodule Lightning.BootstrapTest do
  use Lightning.DataCase, async: false

  alias Lightning.Accounts
  alias Lightning.Bootstrap
  alias Lightning.Credentials.Credential
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectCredential
  alias Lightning.Projects.ProjectUser
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  defp scenario do
    %{
      "users" => [
        %{
          "email" => "owner@openfn.org",
          "first_name" => "Olivia",
          "superuser" => true,
          "api_token" => true
        },
        %{"email" => "editor@openfn.org"}
      ],
      "credentials" => [
        %{
          "name" => "raw-cred",
          "owner" => "owner@openfn.org",
          "schema" => "raw",
          "body" => %{"apiKey" => "sekret"}
        }
      ],
      "projects" => [
        %{
          "name" => "bootstrap-test",
          "members" => [
            %{"email" => "owner@openfn.org", "role" => "owner"},
            %{"email" => "editor@openfn.org", "role" => "editor"}
          ],
          "workflows" => [
            %{
              "name" => "wf-one",
              "trigger" => %{
                "type" => "webhook",
                "webhook_reply" => "after_completion"
              },
              "jobs" => [
                %{"name" => "job-a", "credential" => "raw-cred"},
                %{"name" => "job-b", "body" => "fn(s => s);"}
              ],
              "edges" => [
                %{"from" => "trigger", "to" => "job-a"},
                %{
                  "from" => "job-a",
                  "to" => "job-b",
                  "condition" => "on_job_success"
                }
              ]
            }
          ]
        }
      ]
    }
  end

  describe "run/1" do
    test "creates users, credentials, project, workflow and manifest" do
      result = Bootstrap.run(scenario())

      # users: confirmed, correct roles, api token only where requested
      %{user: owner, api_token: token} = result.users["owner@openfn.org"]
      %{user: editor, api_token: nil} = result.users["editor@openfn.org"]
      assert owner.role == :superuser
      assert owner.confirmed_at
      assert editor.role == :user

      # the api token authenticates like a real one
      assert {:ok, %{"sub" => "user:" <> _}} = Lightning.Tokens.verify(token)

      # default password works for login
      assert Accounts.get_user_by_email_and_password(
               "editor@openfn.org",
               "welcome12345"
             )

      # credential exists and is exposed to the project
      credential = result.credentials["raw-cred"]
      assert credential.user_id == owner.id
      assert credential.schema == "raw"

      [%{project: project, credentials: pc_ids, workflows: [workflow_info]}] =
        result.projects

      pc_id = pc_ids["raw-cred"]

      assert Repo.get_by(ProjectCredential,
               project_id: project.id,
               credential_id: credential.id,
               id: pc_id
             )

      # members and roles
      assert %{role: :owner} =
               Repo.get_by(ProjectUser,
                 project_id: project.id,
                 user_id: owner.id
               )

      assert %{role: :editor} =
               Repo.get_by(ProjectUser,
                 project_id: project.id,
                 user_id: editor.id
               )

      # workflow content, including pass-through trigger fields
      workflow = Repo.get!(Workflow, workflow_info.id)
      assert workflow.name == "wf-one"
      assert workflow.project_id == project.id

      trigger = Repo.get!(Trigger, workflow_info.trigger.id)
      assert trigger.type == :webhook
      assert trigger.enabled
      assert trigger.webhook_reply == :after_completion

      jobs = Repo.all(from j in Job, where: j.workflow_id == ^workflow.id)
      assert length(jobs) == 2

      job_a = Enum.find(jobs, &(&1.name == "job-a"))
      assert job_a.project_credential_id == pc_id
      assert job_a.adaptor == "@openfn/language-common@latest"

      edges = Repo.all(from e in Edge, where: e.workflow_id == ^workflow.id)
      assert length(edges) == 2

      trigger_edge = Enum.find(edges, & &1.source_trigger_id)
      assert trigger_edge.source_trigger_id == trigger.id
      assert trigger_edge.target_job_id == job_a.id
      assert trigger_edge.condition_type == :always

      # manifest carries what a harness needs
      manifest = Bootstrap.manifest(result)

      assert [%{email: "owner@openfn.org", api_token: ^token} | _] =
               Enum.sort_by(manifest.users, & &1.email, :desc)

      assert [%{workflows: [%{trigger: %{webhook_path: webhook_path}}]}] =
               manifest.projects

      assert webhook_path == "/i/#{trigger.id}"

      assert Bootstrap.summary(result) =~ "bootstrap-test"
    end

    test "re-running the same scenario converges instead of duplicating" do
      first = Bootstrap.run(scenario())
      second = Bootstrap.run(scenario())

      # deterministic ids: everything resolves to the same records
      [%{project: p1, workflows: [w1]}] = first.projects
      [%{project: p2, workflows: [w2]}] = second.projects
      assert p1.id == p2.id
      assert w1.id == w2.id
      assert w1.trigger.id == w2.trigger.id
      assert Enum.map(w1.jobs, & &1.id) == Enum.map(w2.jobs, & &1.id)

      # api token is reused, not regenerated
      assert first.users["owner@openfn.org"].api_token ==
               second.users["owner@openfn.org"].api_token

      # no duplicated records
      assert Repo.aggregate(Project, :count) == 1
      assert Repo.aggregate(Workflow, :count) == 1
      assert Repo.aggregate(Trigger, :count) == 1
      assert Repo.aggregate(Job, :count) == 2
      assert Repo.aggregate(Edge, :count) == 2
      assert Repo.aggregate(Credential, :count) == 1

      assert Repo.aggregate(
               from(pu in ProjectUser, where: pu.project_id == ^p1.id),
               :count
             ) == 2
    end

    test "re-running corrects drifted member roles without removing members" do
      Bootstrap.run(scenario())

      updated =
        update_in(
          scenario(),
          ["projects", Access.at(0), "members"],
          fn [owner_member, editor_member] ->
            [owner_member, Map.put(editor_member, "role", "admin")]
          end
        )

      [%{project: project}] = Bootstrap.run(updated).projects

      editor = Accounts.get_user_by_email("editor@openfn.org")

      assert %{role: :admin} =
               Repo.get_by(ProjectUser,
                 project_id: project.id,
                 user_id: editor.id
               )
    end

    test "same-run ownership handover demotes the old owner before promoting the new one" do
      Bootstrap.run(scenario())

      handover =
        update_in(
          scenario(),
          ["projects", Access.at(0), "members"],
          fn [owner_member, editor_member] ->
            [
              Map.put(owner_member, "role", "editor"),
              Map.put(editor_member, "role", "owner")
            ]
          end
        )

      [%{project: project}] = Bootstrap.run(handover).projects

      owner = Accounts.get_user_by_email("owner@openfn.org")
      editor = Accounts.get_user_by_email("editor@openfn.org")

      assert %{role: :editor} =
               Repo.get_by(ProjectUser,
                 project_id: project.id,
                 user_id: owner.id
               )

      assert %{role: :owner} =
               Repo.get_by(ProjectUser,
                 project_id: project.id,
                 user_id: editor.id
               )
    end

    test "rejects more than one declared owner, with a friendly message" do
      two_owners =
        update_in(
          scenario(),
          ["projects", Access.at(0), "members"],
          fn [owner_member, editor_member] ->
            [owner_member, Map.put(editor_member, "role", "owner")]
          end
        )

      assert_raise RuntimeError,
                   ~r/more than one member with\n?\s*role: owner/,
                   fn ->
                     Bootstrap.run(two_owners)
                   end
    end

    test "promoting a new owner while an undeclared owner remains raises a friendly error, not a raw constraint crash" do
      Bootstrap.run(scenario())

      # editor@ is promoted to owner, but owner@ is omitted from this run's
      # members (so, per the never-remove-members contract, they keep their
      # existing owner role) — this must conflict, but cleanly.
      promote_only =
        update_in(
          scenario(),
          ["projects", Access.at(0), "members"],
          fn [_owner_member, editor_member] ->
            [Map.put(editor_member, "role", "owner")]
          end
        )

      assert_raise RuntimeError, ~r/only have one owner|only one owner/, fn ->
        Bootstrap.run(promote_only)
      end
    end

    test "explicit ids win over derived ones" do
      workflow_id = Ecto.UUID.generate()

      scenario =
        put_in(
          scenario(),
          ["projects", Access.at(0), "workflows", Access.at(0), "id"],
          workflow_id
        )

      [%{workflows: [workflow_info]}] = Bootstrap.run(scenario).projects
      assert workflow_info.id == workflow_id
    end

    test "interpolates ${env:VAR} from the environment and fails when unset" do
      System.put_env("BOOTSTRAP_TEST_SECRET", "from-env")
      on_exit(fn -> System.delete_env("BOOTSTRAP_TEST_SECRET") end)

      scenario =
        put_in(
          scenario(),
          ["credentials", Access.at(0), "body", "apiKey"],
          "${env:BOOTSTRAP_TEST_SECRET}"
        )

      result = Bootstrap.run(scenario)

      credential_id = result.credentials["raw-cred"].id

      assert %{body: %{"apiKey" => "from-env"}} =
               Lightning.Credentials.get_credential_body(credential_id, "main")

      missing =
        put_in(
          scenario,
          ["credentials", Access.at(0), "body", "apiKey"],
          "${env:BOOTSTRAP_TEST_UNSET_VAR}"
        )

      assert_raise RuntimeError, ~r/BOOTSTRAP_TEST_UNSET_VAR/, fn ->
        Bootstrap.run(missing)
      end
    end

    test "leaves plain ${...} in job bodies untouched, even uppercase names set in the environment" do
      # HOME is set in virtually every shell — proves interpolation can't
      # collide with a JS template literal even when the name happens to
      # exist in the environment.
      body =
        "fn(s => ({...s, msg: `count is ${count}, home ${HOME}, id ${state.data.id}`}))"

      scenario =
        put_in(
          scenario(),
          [
            "projects",
            Access.at(0),
            "workflows",
            Access.at(0),
            "jobs",
            Access.at(1),
            "body"
          ],
          body
        )

      [%{workflows: [%{jobs: jobs}]}] = Bootstrap.run(scenario).projects
      job_b = Enum.find(jobs, &(&1.name == "job-b"))

      assert Repo.get!(Job, job_b.id).body == body
    end

    test "supports trigger-less workflows via trigger: none" do
      scenario =
        update_in(
          scenario(),
          ["projects", Access.at(0), "workflows", Access.at(0)],
          fn workflow ->
            workflow
            |> Map.put("trigger", "none")
            |> Map.put("edges", [
              %{"from" => "job-a", "to" => "job-b"}
            ])
          end
        )

      [%{workflows: [workflow_info]}] = Bootstrap.run(scenario).projects

      assert workflow_info.trigger == nil
      assert Repo.aggregate(Trigger, :count) == 0
    end

    test "rejects duplicate names and raw triggers keys upfront" do
      duplicate_jobs =
        update_in(
          scenario(),
          ["projects", Access.at(0), "workflows", Access.at(0), "jobs"],
          &[%{"name" => "job-a"} | &1]
        )

      assert_raise RuntimeError, ~r/Duplicate name.*job-a/, fn ->
        Bootstrap.run(duplicate_jobs)
      end

      duplicate_users =
        update_in(
          scenario(),
          ["users"],
          &[%{"email" => "OWNER@openfn.org"} | &1]
        )

      assert_raise RuntimeError, ~r/Duplicate email/, fn ->
        Bootstrap.run(duplicate_users)
      end

      raw_triggers =
        update_in(
          scenario(),
          ["projects", Access.at(0), "workflows", Access.at(0)],
          &(&1 |> Map.delete("trigger") |> Map.put("triggers", []))
        )

      assert_raise RuntimeError, ~r/use the singular "trigger" key/, fn ->
        Bootstrap.run(raw_triggers)
      end
    end

    test "coerces YAML-1.1-style booleans strictly, without silently defaulting to false" do
      # "yes"/"true" (and real booleans) turn superuser/api_token on
      yesses =
        scenario()
        |> put_in(["users", Access.at(0), "email"], "yesses@openfn.org")
        |> put_in(["users", Access.at(0), "superuser"], "yes")
        |> put_in(["users", Access.at(0), "api_token"], "true")
        |> put_in(["credentials", Access.at(0), "owner"], "yesses@openfn.org")
        |> put_in(
          ["projects", Access.at(0), "members", Access.at(0), "email"],
          "yesses@openfn.org"
        )

      result = Bootstrap.run(yesses)
      %{user: owner, api_token: token} = result.users["yesses@openfn.org"]
      assert owner.role == :superuser
      assert is_binary(token)

      # "no"/"false" turn them off explicitly — a fresh user, since existing
      # users are matched (not re-converged) by email
      noes =
        scenario()
        |> put_in(["users", Access.at(0), "email"], "noes@openfn.org")
        |> put_in(["users", Access.at(0), "superuser"], "no")
        |> put_in(["users", Access.at(0), "api_token"], "false")
        |> put_in(["credentials", Access.at(0), "owner"], "noes@openfn.org")
        |> put_in(
          ["projects", Access.at(0), "members", Access.at(0), "email"],
          "noes@openfn.org"
        )
        |> put_in(["projects", Access.at(0), "name"], "noes-project")

      result = Bootstrap.run(noes)
      %{user: owner, api_token: token} = result.users["noes@openfn.org"]
      assert owner.role == :user
      assert token == nil

      # anything else raises rather than silently defaulting to false
      garbage =
        scenario()
        |> put_in(["users", Access.at(0), "email"], "garbage@openfn.org")
        |> put_in(["users", Access.at(0), "superuser"], "on")

      assert_raise RuntimeError, ~r/Expected superuser for user.*boolean/, fn ->
        Bootstrap.run(garbage)
      end
    end

    test "supports project description and collections" do
      scenario =
        scenario()
        |> put_in(
          ["projects", Access.at(0), "description"],
          "a test project"
        )
        |> put_in(
          ["projects", Access.at(0), "collections"],
          [%{"name" => "my-collection"}]
        )

      [%{project: project}] = Bootstrap.run(scenario).projects

      project = Repo.get!(Project, project.id)
      assert project.description == "a test project"

      assert Repo.get_by(Lightning.Collections.Collection,
               project_id: project.id,
               name: "my-collection"
             )
    end

    test "rejects unknown keys instead of silently ignoring them" do
      # top level: typo'd section name
      assert_raise RuntimeError, ~r/Unknown key\(s\) for scenario: usres/, fn ->
        scenario()
        |> Map.put("usres", [])
        |> Map.delete("users")
        |> Bootstrap.run()
      end

      # user level
      with_bad_user_key =
        update_in(scenario(), ["users", Access.at(0)], &Map.put(&1, "rol", "x"))

      assert_raise RuntimeError,
                   ~r/Unknown key\(s\) for user owner@openfn.org: rol/,
                   fn ->
                     Bootstrap.run(with_bad_user_key)
                   end

      # credential level
      with_bad_credential_key =
        update_in(
          scenario(),
          ["credentials", Access.at(0)],
          &Map.put(&1, "shcema", "raw")
        )

      assert_raise RuntimeError,
                   ~r/Unknown key\(s\) for credential raw-cred: shcema/,
                   fn ->
                     Bootstrap.run(with_bad_credential_key)
                   end

      # project level: a real provisioner field we don't support yet — the
      # error should name it, not silently drop it
      with_channels =
        put_in(scenario(), ["projects", Access.at(0), "channels"], [])

      assert_raise RuntimeError,
                   ~r/Unknown key\(s\) for project bootstrap-test: channels/,
                   fn -> Bootstrap.run(with_channels) end

      # member level
      with_bad_member_key =
        update_in(
          scenario(),
          ["projects", Access.at(0), "members", Access.at(0)],
          &Map.put(&1, "roel", "owner")
        )

      assert_raise RuntimeError,
                   ~r/Unknown key\(s\) for member owner@openfn.org/,
                   fn ->
                     Bootstrap.run(with_bad_member_key)
                   end
    end

    test "raises clear errors for invalid scenarios, rolling back" do
      # member email not declared under users
      undeclared =
        update_in(
          scenario(),
          ["projects", Access.at(0), "members"],
          &[%{"email" => "ghost@openfn.org", "role" => "owner"} | &1]
        )

      assert_raise RuntimeError, ~r/ghost@openfn.org/, fn ->
        Bootstrap.run(undeclared)
      end

      # nothing was left behind by the failed run
      assert Repo.aggregate(Project, :count) == 0

      # edge referencing a job that doesn't exist
      bad_edge =
        update_in(
          scenario(),
          ["projects", Access.at(0), "workflows", Access.at(0), "edges"],
          &[%{"from" => "trigger", "to" => "nope"} | &1]
        )

      assert_raise RuntimeError, ~r/"nope"/, fn -> Bootstrap.run(bad_edge) end

      # projects need an owner
      no_owner =
        put_in(
          scenario(),
          ["projects", Access.at(0), "members"],
          [%{"email" => "editor@openfn.org", "role" => "editor"}]
        )

      assert_raise RuntimeError, ~r/role: owner/, fn ->
        Bootstrap.run(no_owner)
      end

      # unknown provisioner fields fail loudly rather than being dropped
      typo =
        put_in(
          scenario(),
          ["projects", Access.at(0), "workflows", Access.at(0), "trigger"],
          %{"type" => "webhook", "webook_replyy" => "yes"}
        )

      assert_raise RuntimeError, ~r/extraneous parameters/i, fn ->
        Bootstrap.run(typo)
      end
    end

    test "raises when bootstrapping is disabled" do
      original = Application.get_env(:lightning, Bootstrap)
      Application.put_env(:lightning, Bootstrap, enabled: false)
      on_exit(fn -> Application.put_env(:lightning, Bootstrap, original) end)

      assert_raise RuntimeError, ~r/Lightning.Bootstrap is disabled/, fn ->
        Bootstrap.run(scenario())
      end
    end
  end

  describe "run_file/2" do
    @tag tmp_dir: true
    test "loads yaml, runs it and writes a manifest", %{tmp_dir: tmp_dir} do
      scenario_path = Path.join(tmp_dir, "scenario.yaml")
      manifest_path = Path.join(tmp_dir, "manifest.json")

      File.write!(scenario_path, """
      users:
        - email: yaml@openfn.org
          api_token: true
      projects:
        - name: yaml-project
          members:
            - { email: yaml@openfn.org, role: owner }
          workflows:
            - name: yaml-workflow
              trigger:
                type: cron
                cron_expression: "0 * * * *"
              jobs:
                - name: yaml-job
              edges:
                - { from: trigger, to: yaml-job }
      """)

      result = Bootstrap.run_file(scenario_path, manifest: manifest_path)

      [%{workflows: [%{trigger: %{id: trigger_id}}]}] = result.projects
      assert %{type: :cron} = Repo.get!(Trigger, trigger_id)

      manifest = manifest_path |> File.read!() |> Jason.decode!()

      assert [%{"email" => "yaml@openfn.org", "api_token" => token}] =
               manifest["users"]

      assert is_binary(token)

      # cron triggers have no webhook path
      assert [%{"workflows" => [%{"trigger" => %{"webhook_path" => nil}}]}] =
               manifest["projects"]
    end

    test "the checked-in example scenario stays runnable" do
      result = Bootstrap.run_file("bin/e2e.d/scenarios/example.yaml")

      assert [%{project: %{name: "example-project"}}] = result.projects
      assert result.users |> Map.keys() |> length() == 3
    end

    test "rejects unsupported file extensions" do
      assert_raise RuntimeError, ~r/Unsupported scenario file extension/, fn ->
        Bootstrap.run_file(__ENV__.file)
      end
    end
  end
end
