defmodule Lightning.Projects.ProvisionerTest do
  use Lightning.DataCase, async: true

  alias Lightning.Projects.Provisioner
  alias Lightning.ProjectsFixtures

  describe "parse_document/2 with a new project" do
    test "with invalid data" do
      changeset = Provisioner.parse_document(%Lightning.Projects.Project{}, %{})

      assert {:id, {"can't be blank", [validation: :required]}} in changeset.errors

      assert {:name, {"can't be blank", [validation: :required]}} in changeset.errors

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

      nested_errors =
        Ecto.Changeset.traverse_errors(changeset, fn {field, _message} ->
          field
        end)

      assert nested_errors == %{
               workflows: [
                 %{
                   jobs: [
                     %{id: ["can't be blank"]},
                     %{id: ["can't be blank"]}
                   ]
                 }
               ]
             }
    end

    test "with valid data" do
      %{
        body: body,
        project_id: project_id,
        workflow_id: workflow_id,
        first_job_id: first_job_id,
        second_job_id: second_job_id
      } = valid_document()

      {:ok, project} =
        Provisioner.import_document(%Lightning.Projects.Project{}, body)

      assert %{id: ^project_id, workflows: [workflow]} = project

      assert %{id: ^workflow_id, jobs: jobs} = workflow

      assert MapSet.equal?(
               jobs |> MapSet.new(& &1.id),
               MapSet.new([first_job_id, second_job_id])
             ),
             "Should have both the first and second jobs"
    end
  end

  describe "import_document/2 with an existing project" do
    setup do
      %{project: ProjectsFixtures.project_fixture()}
    end

    test "changing, adding records", %{project: project} do
      %{body: body} = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, body)

      assert project.workflows |> Enum.at(0) |> Map.get(:edges) |> length() == 1

      third_job_id = Ecto.UUID.generate()

      body =
        body
        |> Map.put("name", "test-project-renamed")
        |> add_job_to_document(%{
          "id" => third_job_id,
          "name" => "third-job",
          "adaptor" => "@openfn/language-common@latest"
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

      {:ok, project} = Provisioner.import_document(project, body)

      assert project.workflows
             |> Enum.at(0)
             |> then(fn w -> w.jobs end)
             |> Enum.any?(&(&1.id == third_job_id)),
             "The third job should be added"
    end

    test "removing a record", %{project: project} do
      %{
        body: body,
        second_job_id: second_job_id
      } = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, body)

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

      {:ok, project} = Provisioner.import_document(project, body)

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

    test "removing a workflow", %{project: project} do
      %{
        body: body,
        workflow_id: workflow_id
      } = valid_document(project.id)

      {:ok, project} = Provisioner.import_document(project, body)
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

      {:ok, project} = Provisioner.import_document(project, body)

      assert project.workflows == [],
             "The workflow should be removed from the project"
    end

    test "marking a new/changed record for deletion", %{project: project} do
      body = %{
        "id" => project.id,
        "name" => "test-project",
        "workflows" => [
          %{"delete" => true, "name" => "default", "id" => Ecto.UUID.generate()}
        ]
      }

      {:error, changeset} = Provisioner.import_document(project, body)

      refute changeset.valid?

      workflow_errors =
        changeset
        |> Ecto.Changeset.get_change(:workflows)
        |> Enum.at(0)
        |> then(& &1.errors)

      assert {:delete, {"cannot change or add a record while deleting", []}} in workflow_errors
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
              "adaptor" => "@openfn/language-common@latest"
            },
            %{
              "id" => second_job_id,
              "name" => "second-job",
              "adaptor" => "@openfn/language-common@latest"
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
