defmodule Lightning.Projects.ProvisionerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing.Audit
  alias Lightning.Projects.Provisioner
  alias Lightning.ProjectsFixtures
  alias Lightning.Workflows.Snapshot

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.CoreComponents, only: [translate_error: 1]

  describe "parse_document/2 with a new project" do
    test "with invalid data" do
      Mox.verify_on_exit!()

      changeset = Provisioner.parse_document(%Lightning.Projects.Project{}, %{})

      assert flatten_errors(changeset) == %{
               id: ["This field can't be blank."],
               name: ["This field can't be blank."]
             }

      %{body: body} = valid_document()

      body =
        body
        |> Map.update!("workflows", fn workflows ->
          workflows
          |> Enum.map(fn workflow ->
            workflow
            |> Map.update!("jobs", fn jobs ->
              jobs
              |> Enum.map(fn job ->
                job |> Map.drop(["id"])
              end)
            end)
          end)
        end)

      Mox.expect(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      changeset = Provisioner.parse_document(%Lightning.Projects.Project{}, body)

      refute changeset.valid?

      assert flatten_errors(changeset) == %{
               workflows: [
                 %{
                   jobs: [
                     %{id: ["This field can't be blank."]},
                     %{id: ["This field can't be blank."]}
                   ]
                 }
               ]
             }
    end

    test "with extraneous fields" do
      changeset =
        Provisioner.parse_document(%Lightning.Projects.Project{}, %{
          "foo" => "bar",
          "baz" => "qux"
        })

      assert flatten_errors(changeset) == %{
               id: ["This field can't be blank."],
               name: ["This field can't be blank."],
               base: ["extraneous parameters: baz, foo"]
             }
    end

    test "with sensitive kafka trigger fields" do
      %{body: body} = valid_document()

      body =
        body
        |> Map.update!("workflows", fn workflows ->
          workflows
          |> Enum.map(fn workflow ->
            workflow
            |> Map.update!("triggers", fn [trigger] ->
              [
                Map.merge(trigger, %{
                  "type" => "kafka",
                  "kafka_configuration" => %{
                    "hosts" => [["localhost", "9092"]],
                    "topics" => ["topic"],
                    "initial_offset_reset_policy" => "earliest",
                    "username" => "heyoo",
                    "password" => "secret"
                  }
                })
              ]
            end)
          end)
        end)

      changeset =
        Provisioner.parse_document(%Lightning.Projects.Project{}, body)

      assert %{
               workflows: [
                 %{
                   triggers: [
                     %{
                       kafka_configuration: %{
                         username: [
                           "credentials can only be changed through the dashboard"
                           | _
                         ],
                         password: [
                           "credentials can only be changed through the dashboard"
                           | _
                         ]
                       }
                     }
                   ]
                 }
               ]
             } = flatten_errors(changeset)
    end
  end

  describe "import_document/2 with a new project" do
    test "with valid data" do
      Mox.verify_on_exit!()
      user = insert(:user)

      credential = insert(:credential, name: "Test Credential", user: user)

      %{
        body: %{"workflows" => [workflow]} = body,
        project_id: project_id,
        workflows: [
          %{
            id: workflow_id,
            first_job_id: first_job_id,
            second_job_id: second_job_id
          }
        ]
      } = valid_document()

      project_credential_id = Ecto.UUID.generate()

      credentials_payload =
        [
          %{
            "id" => project_credential_id,
            "name" => credential.name,
            "owner" => user.email
          }
        ]

      updated_workflow_jobs =
        Enum.map(workflow["jobs"], fn job ->
          if job["id"] == first_job_id do
            job
            |> Map.put("project_credential_id", project_credential_id)
          else
            job
          end
        end)

      body_with_credentials =
        body
        |> Map.put("project_credentials", credentials_payload)
        |> Map.put("workflows", [%{workflow | "jobs" => updated_workflow_jobs}])

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      {:ok, project} =
        Provisioner.import_document(
          %Lightning.Projects.Project{},
          user,
          body_with_credentials
        )

      assert %{
               id: ^project_id,
               workflows: [workflow],
               project_credentials: [project_credential]
             } = project

      assert %{id: ^project_credential_id} = project_credential

      assert %{id: ^workflow_id, jobs: jobs} = workflow

      assert MapSet.equal?(
               jobs |> MapSet.new(& &1.id),
               MapSet.new([first_job_id, second_job_id])
             ),
             "Should have both the first and second jobs"

      assert %Snapshot{} = Snapshot.get_current_for(workflow)

      project = project |> Lightning.Repo.preload(:project_users)

      assert project.project_users
             |> Enum.any?(fn pu ->
               pu.user_id == user.id && pu.role == :owner
             end)
    end

    test "audit the creation of a snapshot" do
      Mox.verify_on_exit!()
      %{id: user_id} = user = insert(:user)

      credential = insert(:credential, name: "Test Credential", user: user)

      %{
        body: %{"workflows" => [workflow]} = body,
        workflows: [
          %{
            id: workflow_id,
            first_job_id: first_job_id
          }
        ]
      } = valid_document()

      project_credential_id = Ecto.UUID.generate()

      credentials_payload =
        [
          %{
            "id" => project_credential_id,
            "name" => credential.name,
            "owner" => user.email
          }
        ]

      updated_workflow_jobs =
        Enum.map(workflow["jobs"], fn job ->
          if job["id"] == first_job_id do
            job
            |> Map.put("project_credential_id", project_credential_id)
          else
            job
          end
        end)

      body_with_credentials =
        body
        |> Map.put("project_credentials", credentials_payload)
        |> Map.put("workflows", [%{workflow | "jobs" => updated_workflow_jobs}])

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, _context -> :ok end
      )

      Provisioner.import_document(
        %Lightning.Projects.Project{},
        user,
        body_with_credentials
      )

      %{id: snapshot_id} = Repo.one!(Snapshot)

      audit = Repo.one!(from a in Audit, where: a.event == "snapshot_created")

      assert %{
               item_id: ^workflow_id,
               actor_id: ^user_id,
               changes: %{
                 after: %{
                   "snapshot_id" => ^snapshot_id
                 }
               }
             } = audit
    end
  end

  describe "import_document/2 with an existing project" do
    setup do
      Mox.verify_on_exit!()
      %{project: ProjectsFixtures.project_fixture(), user: insert(:user)}
    end

    test "doesn't add another project user", %{
      project: %{id: project_id} = project,
      user: user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      %{body: body} = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, user, body)

      project = project |> Lightning.Repo.preload(:project_users)

      assert project.project_users
             |> Enum.any?(fn pu ->
               pu.user_id == user.id && pu.role == :owner
             end)

      user2 = insert(:user)

      {:ok, project} = Provisioner.import_document(project, user2, body)

      project = project |> Lightning.Repo.preload(:project_users)

      project_user_ids = project.project_users |> Enum.map(& &1.user_id)
      assert user.id in project_user_ids
      refute user2.id in project_user_ids
    end

    test "audit the creation of a snapshot", %{
      project: %{id: project_id} = project,
      user: %{id: user_id} = user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      %{body: body, workflows: [%{id: workflow_id}]} = valid_document(project.id)

      {:ok, _project} = Provisioner.import_document(project, user, body)

      %{id: snapshot_id} = Snapshot |> Repo.one!()

      audit = Repo.one!(from a in Audit, where: a.event == "snapshot_created")

      assert %{
               item_id: ^workflow_id,
               actor_id: ^user_id,
               changes: %{
                 after: %{
                   "snapshot_id" => ^snapshot_id
                 }
               }
             } = audit
    end

    test "changing, adding records", %{
      project: %{id: project_id} = project,
      user: user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      %{body: body, workflows: [%{id: workflow_id}]} = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, user, body)

      assert project.workflows |> Enum.at(0) |> Map.get(:edges) |> length() == 2

      snapshots_before =
        Enum.map(project.workflows, fn workflow ->
          Snapshot.get_current_for(workflow)
        end)

      assert [
               %Snapshot{
                 lock_version: 1,
                 jobs: jobs,
                 triggers: triggers,
                 edges: edges
               }
             ] = snapshots_before

      assert Enum.count(jobs) == 2
      assert Enum.count(triggers) == 1
      assert Enum.count(edges) == 2

      third_job_id = Ecto.UUID.generate()

      body =
        body
        |> Map.put("name", "test-project-renamed")
        |> add_job_to_document(workflow_id, %{
          "id" => third_job_id,
          "name" => "third-job",
          "adaptor" => "@openfn/language-common@latest",
          "body" => "console.log('hello world');"
        })

      changeset = Provisioner.parse_document(project, body)

      new_job_changeset =
        changeset
        |> Ecto.Changeset.get_change(:workflows)
        |> Enum.at(0)
        |> Ecto.Changeset.get_change(:jobs)
        |> Enum.at(0)

      assert %{action: :insert, changes: %{id: ^third_job_id}} =
               new_job_changeset

      {:ok, project} = Provisioner.import_document(project, user, body)

      assert project.workflows
             |> Enum.at(0)
             |> then(fn w -> w.jobs end)
             |> Enum.any?(&(&1.id == third_job_id)),
             "The third job should be added"

      snapshots_after =
        Enum.map(project.workflows, fn workflow ->
          Snapshot.get_current_for(workflow)
        end)

      assert [
               %Snapshot{
                 lock_version: 2,
                 jobs: jobs,
                 triggers: triggers,
                 edges: edges
               }
             ] = snapshots_after

      assert Enum.count(jobs) == 3
      assert Enum.count(triggers) == 1
      assert Enum.count(edges) == 2
    end

    test "adding a record from another project or workflow", %{
      project: %{id: project_id} = project,
      user: user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      %{body: body, workflows: [%{id: workflow_id}]} = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, user, body)

      assert project.workflows |> Enum.at(0) |> Map.get(:edges) |> length() == 2

      %{id: third_job_id} = Lightning.Factories.insert(:job)

      {:error, changeset} =
        Provisioner.import_document(
          project,
          user,
          body
          |> add_entity_to_workflow(workflow_id, "jobs", %{
            "id" => third_job_id,
            "name" => "third-job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "console.log('hello world');"
          })
        )

      assert flatten_errors(changeset) == %{
               workflows: [
                 %{
                   jobs: [
                     %{id: ["This email address already exists."]},
                     %{},
                     %{}
                   ]
                 }
               ]
             }

      %{id: other_trigger_id} = Lightning.Factories.insert(:trigger)

      {:error, changeset} =
        Provisioner.import_document(
          project,
          user,
          body
          |> add_entity_to_workflow(workflow_id, "triggers", %{
            "id" => other_trigger_id
          })
        )

      assert flatten_errors(changeset) == %{
               workflows: [
                 %{
                   triggers: [%{id: ["This email address already exists."]}, %{}]
                 }
               ]
             }

      %{id: other_edge_id} = Lightning.Factories.insert(:edge)

      {:error, changeset} =
        Provisioner.import_document(
          project,
          user,
          body
          |> add_entity_to_workflow(workflow_id, "edges", %{
            "id" => other_edge_id,
            "source_job_id" => third_job_id,
            "condition_type" => "on_job_success"
          })
        )

      assert flatten_errors(changeset) == %{
               workflows: [
                 %{
                   edges: [
                     %{id: ["This email address already exists."]},
                     %{},
                     %{}
                   ]
                 }
               ]
             }
    end

    test "fails when an edge has no source", %{
      project: %{id: project_id} = project,
      user: user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      %{body: body, workflows: [%{id: workflow_id}]} = valid_document(project.id)

      %{id: other_edge_id} = Lightning.Factories.insert(:edge)

      {:error, changeset} =
        Provisioner.import_document(
          project,
          user,
          body
          |> add_entity_to_workflow(workflow_id, "edges", %{
            "id" => other_edge_id,
            "condition_type" => "on_job_success"
          })
        )

      assert flatten_errors(changeset) == %{
               workflows: [
                 %{
                   edges: [
                     %{
                       source_job_id: [
                         "source_job_id or source_trigger_id must be present"
                       ]
                     },
                     %{},
                     %{}
                   ]
                 }
               ]
             }
    end

    test "removing a record", %{project: %{id: project_id} = project, user: user} do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      %{
        body: body,
        workflows: [%{second_job_id: second_job_id}]
      } = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, user, body)

      body = body |> remove_job_from_document(second_job_id)

      changeset = Provisioner.parse_document(project, body)

      new_job_changeset =
        changeset
        |> Ecto.Changeset.get_change(:workflows)
        |> Enum.at(0)
        |> Ecto.Changeset.get_change(:jobs)

      assert %{action: :delete} =
               new_job_changeset
               |> Enum.find(fn job_changeset ->
                 job_changeset |> Ecto.Changeset.get_field(:id) == second_job_id
               end),
             "The second job should be marked for deletion"

      {:ok, project} = Provisioner.import_document(project, user, body)

      workflow_job_ids =
        project.workflows
        |> Enum.at(0)
        |> then(fn w -> w.jobs end)
        |> Enum.into([], & &1.id)

      refute second_job_id in workflow_job_ids

      edges =
        project.workflows
        |> Enum.at(0)
        |> then(& &1.edges)

      assert edges |> length() == 1

      refute edges |> Enum.any?(&(&1.source_job_id == second_job_id)),
             "The edge associated with the deleted job should be removed"
    end

    test "removing a workflow", %{
      project: %{id: project_id} = project,
      user: user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      %{
        body: body,
        workflows: [%{id: workflow_id}]
      } = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, user, body)
      body = body |> remove_workflow_from_document(workflow_id)

      changeset = Provisioner.parse_document(project, body)

      assert %{action: :delete} =
               changeset
               |> Ecto.Changeset.get_change(:workflows)
               |> Enum.find(fn workflow_changeset ->
                 workflow_changeset |> Ecto.Changeset.get_field(:id) ==
                   workflow_id
               end),
             "The workflow should be marked for deletion"

      {:ok, project} = Provisioner.import_document(project, user, body)

      assert project.workflows == [],
             "The workflow should be removed from the project"
    end

    test "marking a new/changed record for deletion", %{
      project: %{id: project_id} = project,
      user: user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      body = %{
        "id" => project.id,
        "name" => "test-project",
        "workflows" => [
          %{"delete" => true, "name" => "default", "id" => Ecto.UUID.generate()}
        ]
      }

      {:error, changeset} = Provisioner.import_document(project, user, body)

      refute changeset.valid?

      assert flatten_errors(changeset) == %{
               workflows: [
                 %{delete: ["cannot change or add a record while deleting"]}
               ]
             }
    end

    test "adds error incase limit action is returns error", %{
      project: %{id: project_id} = project,
      user: user
    } do
      %{body: body} = valid_document(project_id)
      error_msg = "Oopsie Doopsie"

      Lightning.Extensions.MockUsageLimiter
      |> Mox.expect(
        :limit_action,
        fn %{type: :github_sync}, %{project_id: ^project_id} -> :ok end
      )
      |> Mox.expect(
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          {:error, :too_many_workflows, %{text: error_msg}}
        end
      )

      assert {:error, changeset} =
               Provisioner.import_document(project, user, body)

      assert flatten_errors(changeset) == %{id: [error_msg]}
    end

    test "sends workflow updated event", %{
      project: %{id: project_id} = project,
      user: user
    } do
      %{body: body, workflows: [%{id: workflow_id}]} = valid_document(project.id)

      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :limit_action,
        fn _action, %{project_id: ^project_id} ->
          :ok
        end
      )

      Lightning.Workflows.subscribe(project.id)

      assert {:ok, _project} =
               Provisioner.import_document(project, user, body)

      assert_received %Lightning.Workflows.Events.WorkflowUpdated{
        workflow: %{id: ^workflow_id}
      }
    end
  end

  defp valid_document(project_id \\ nil, number_of_workflows \\ 1) do
    project_id = project_id || Ecto.UUID.generate()

    [workflows, workflow_properties] =
      1..number_of_workflows
      |> Enum.map(&valid_workflow/1)
      |> Enum.unzip()
      |> Tuple.to_list()

    body = %{
      "id" => project_id,
      "name" => "test-project",
      "workflows" => workflows
    }

    %{
      body: body,
      project_id: project_id,
      workflows: workflow_properties
    }
  end

  defp valid_workflow(index) do
    first_job_id = Ecto.UUID.generate()
    second_job_id = Ecto.UUID.generate()
    trigger_id = Ecto.UUID.generate()
    workflow_id = Ecto.UUID.generate()
    trigger_edge_id = Ecto.UUID.generate()
    job_edge_id = Ecto.UUID.generate()

    workflow =
      %{
        "id" => workflow_id,
        "name" => "default-#{index}",
        "jobs" => [
          %{
            "id" => first_job_id,
            "name" => "first-job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "console.log('hello world');"
          },
          %{
            "id" => second_job_id,
            "name" => "second-job",
            "adaptor" => "@openfn/language-common@latest",
            "body" => "console.log('hello world');"
          }
        ],
        "triggers" => [
          %{
            "id" => trigger_id,
            "enabled" => true
          }
        ],
        "edges" => [
          %{
            "id" => trigger_edge_id,
            "source_trigger_id" => trigger_id,
            "condition_label" => "Always",
            "condition_type" => "js_expression",
            "condition_expression" => "true"
          },
          %{
            "id" => job_edge_id,
            "source_job_id" => first_job_id,
            "condition_type" => "on_job_success",
            "target_job_id" => second_job_id
          }
        ]
      }

    {
      workflow,
      %{
        id: workflow_id,
        first_job_id: first_job_id,
        second_job_id: second_job_id,
        trigger_id: trigger_id,
        job_edge_id: job_edge_id
      }
    }
  end

  defp flatten_errors(changeset) do
    Ecto.Changeset.traverse_errors(
      changeset,
      &translate_error/1
    )
  end

  defp add_job_to_document(document, workflow_id, job_params) do
    document
    |> Map.update!("workflows", fn workflows ->
      workflows
      |> Enum.map(fn workflow ->
        if workflow["id"] == workflow_id do
          workflow
          |> Map.update!("jobs", fn jobs ->
            [job_params | jobs]
          end)
        else
          workflow
        end
      end)
    end)
  end

  defp add_entity_to_workflow(document, workflow_id, key, params) do
    document
    |> Map.update!("workflows", fn workflows ->
      i = Enum.find_index(workflows, &match?(%{"id" => ^workflow_id}, &1))

      workflows
      |> Enum.at(i)
      |> Map.update!(key, fn es ->
        [params | es]
      end)
      |> then(fn workflow ->
        List.replace_at(workflows, i, workflow)
      end)
    end)
  end

  defp remove_job_from_document(document, id) do
    document
    |> Map.update!("workflows", fn workflows ->
      Enum.at(workflows, 0)
      |> Map.update!("jobs", fn jobs ->
        jobs
        |> Enum.map(fn job ->
          if job["id"] == id do
            Map.put(job, "delete", true)
          else
            job
          end
        end)
      end)
      |> then(fn workflow ->
        List.replace_at(workflows, 0, workflow)
      end)
    end)
  end

  defp remove_workflow_from_document(document, id) do
    document
    |> Map.update!("workflows", fn workflows ->
      workflows
      |> Enum.map(fn workflow ->
        if workflow["id"] == id do
          Map.put(workflow, "delete", true)
        else
          workflow
        end
      end)
    end)
  end
end
