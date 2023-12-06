defmodule Lightning.Projects.ProvisionerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Provisioner
  alias Lightning.ProjectsFixtures
  import Lightning.Factories
  import LightningWeb.CoreComponents, only: [translate_error: 1]

  describe "parse_document/2 with a new project" do
    test "with invalid data" do
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
  end

  describe "import_document/2 with a new project" do
    test "with valid data" do
      user = insert(:user)

      %{
        body: body,
        project_id: project_id,
        workflow_id: workflow_id,
        first_job_id: first_job_id,
        second_job_id: second_job_id
      } = valid_document()

      {:ok, project} =
        Provisioner.import_document(%Lightning.Projects.Project{}, user, body)

      assert %{id: ^project_id, workflows: [workflow]} = project

      assert %{id: ^workflow_id, jobs: jobs} = workflow

      assert MapSet.equal?(
               jobs |> MapSet.new(& &1.id),
               MapSet.new([first_job_id, second_job_id])
             ),
             "Should have both the first and second jobs"

      project = project |> Lightning.Repo.preload(:project_users)

      assert project.project_users
             |> Enum.any?(fn pu ->
               pu.user_id == user.id && pu.role == :owner
             end)
    end
  end

  describe "import_document/2 with an existing project" do
    setup do
      %{project: ProjectsFixtures.project_fixture(), user: insert(:user)}
    end

    test "doesn't add another project user", %{project: project, user: user} do
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

    test "changing, adding records", %{project: project, user: user} do
      %{body: body} = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, user, body)

      assert project.workflows |> Enum.at(0) |> Map.get(:edges) |> length() == 1

      third_job_id = Ecto.UUID.generate()

      body =
        body
        |> Map.put("name", "test-project-renamed")
        |> add_job_to_document(%{
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
    end

    test "adding a record from another project or workflow", %{
      project: project,
      user: user
    } do
      %{body: body, workflow_id: workflow_id} = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, user, body)

      assert project.workflows |> Enum.at(0) |> Map.get(:edges) |> length() == 1

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
                 %{jobs: [%{id: ["This email address already exists."]}]}
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
                 %{triggers: [%{id: ["This email address already exists."]}]}
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
            "condition" => "on_job_success"
          })
        )

      assert flatten_errors(changeset) == %{
               workflows: [
                 %{edges: [%{id: ["This email address already exists."]}]}
               ]
             }
    end

    test "removing a record", %{project: project, user: user} do
      %{
        body: body,
        second_job_id: second_job_id
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

      assert project.workflows
             |> Enum.at(0)
             |> then(fn w -> w.edges end) == [],
             "The edge associated with the deleted job should be removed"
    end

    test "removing a workflow", %{project: project, user: user} do
      %{
        body: body,
        workflow_id: workflow_id
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
      project: project,
      user: user
    } do
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
  end

  defp valid_document(project_id \\ nil) do
    project_id = project_id || Ecto.UUID.generate()
    first_job_id = Ecto.UUID.generate()
    second_job_id = Ecto.UUID.generate()
    trigger_id = Ecto.UUID.generate()
    workflow_id = Ecto.UUID.generate()
    job_edge_id = Ecto.UUID.generate()

    body = %{
      "id" => project_id,
      "name" => "test-project",
      "workflows" => [
        %{
          "id" => workflow_id,
          "name" => "default",
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
              "id" => trigger_id
            }
          ],
          "edges" => [
            %{
              "id" => job_edge_id,
              "source_job_id" => first_job_id,
              "condition" => "on_job_success",
              "target_job_id" => second_job_id
            }
          ]
        }
      ]
    }

    %{
      body: body,
      project_id: project_id,
      workflow_id: workflow_id,
      first_job_id: first_job_id,
      second_job_id: second_job_id,
      trigger_id: trigger_id,
      job_edge_id: job_edge_id
    }
  end

  defp flatten_errors(changeset) do
    Ecto.Changeset.traverse_errors(
      changeset,
      &translate_error/1
    )
  end

  defp add_job_to_document(document, job_params) do
    document
    |> Map.update!("workflows", fn workflows ->
      Enum.at(workflows, 0)
      |> Map.update!("jobs", fn jobs ->
        [job_params | jobs]
      end)
      |> then(fn workflow ->
        List.replace_at(workflows, 0, workflow)
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
