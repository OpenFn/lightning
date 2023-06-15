defmodule Lightning.JobsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Jobs` context.
  """

  import Lightning.ProjectsFixtures
  import Lightning.WorkflowsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.Factories

  @doc """
  Generate a job.
  """
  @spec job_fixture(attrs :: Keyword.t()) :: Lightning.Jobs.Job.t()
  def job_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:project_id, fn -> project_fixture().id end)

    attrs =
      attrs
      |> Keyword.put_new_lazy(:workflow_id, fn ->
        workflow_fixture(project_id: attrs[:project_id]).id
      end)

    {:ok, job} =
      attrs
      |> Enum.into(%{
        body: "fn(state => state)",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common"
      })
      |> Lightning.Jobs.create_job()

    job
  end

  defp random_name() do
    suffix =
      Ecto.UUID.generate() |> String.split_at(5) |> then(fn {x, _} -> x end)

    "Untitled-#{suffix}"
  end

  def workflow_job_fixture(attrs \\ []) do
    workflow =
      Ecto.Changeset.cast(
        %Lightning.Workflows.Workflow{},
        %{
          "name" =>
            attrs[:workflow_name] ||
              random_name(),
          "project_id" => attrs[:project_id] || project_fixture().id,
          "id" => Ecto.UUID.generate()
        },
        [:project_id, :id, :name]
      )

    project_credential =
      project_credential_fixture(
        name: "my first cred",
        body: %{"shhh" => "secret-stuff"}
      )

    attrs =
      attrs
      |> Enum.into(%{
        body: "fn(state => state)",
        enabled: true,
        name: "some name",
        adaptor: "@openfn/language-common",
        project_credential_id: project_credential.id,
        trigger: %{type: "webhook"}
      })

    job =
      %Lightning.Jobs.Job{}
      |> Ecto.Changeset.change()
      |> Lightning.Jobs.Job.put_workflow(workflow)
      |> Lightning.Jobs.Job.changeset(attrs)
      |> Lightning.Repo.insert!()

    t =
      insert(:trigger,
        workflow: job.workflow,
        type: :webhook
      )

    e =
      insert(:edge,
        source_trigger: t,
        target_job: job,
        workflow: job.workflow,
        condition: :always
      )

    %{job: job, edge: e, trigger: t}
  end

  def workflow_scenario() do
    project = project_fixture()
    workflow = workflow_fixture(project_id: project.id)

    #       +---+
    #   +---- A ----+
    #   |   +---+   |
    #   |           |
    #   |           |
    #   |           |
    # +-|-+       +-|-+
    # | B |       | E |
    # +-|-+       +-|-+
    #   |           |
    #   |           |
    # +-+-+       +-+-+
    # | C |       | F |
    # +-|-+       +-|-+
    #   |           |
    #   |           |
    # +-+-+       +-+-+
    # | D |       | G |
    # +---+       +---+
    #

    trigger =
      insert(:trigger, %{
        workflow: workflow,
        type: :webhook
      })

    job_a =
      job_fixture(
        name: "job_a",
        workflow_id: workflow.id
      )

    edge_t_a =
      insert(:edge, %{
        workflow: workflow,
        source_trigger_id: trigger.id,
        target_job_id: job_a.id
      })

    job_b =
      job_fixture(
        name: "job_b",
        workflow_id: workflow.id
      )

    edge_a_b =
      insert(:edge, %{
        workflow: workflow,
        source_job_id: job_a.id,
        target_job_id: job_b.id,
        condition: :on_job_success
      })

    job_c =
      job_fixture(
        name: "job_c",
        workflow: workflow
      )

    edge_b_c =
      insert(:edge, %{
        workflow: workflow,
        source_job_id: job_b.id,
        target_job_id: job_c.id,
        condition: :on_job_success
      })

    job_d =
      job_fixture(
        name: "job_d",
        workflow: workflow
      )

    edge_c_d =
      insert(:edge, %{
        workflow: workflow,
        source_job_id: job_c.id,
        target_job_id: job_d.id,
        condition: :on_job_success
      })

    job_e =
      job_fixture(
        name: "job_e",
        workflow: workflow
      )

    edge_a_e =
      insert(:edge, %{
        workflow: workflow,
        source_job_id: job_a.id,
        target_job_id: job_e.id,
        condition: :on_job_success
      })

    job_f =
      job_fixture(
        name: "job_f",
        workflow: workflow
      )

    edge_e_f =
      insert(:edge, %{
        workflow: workflow,
        source_job_id: job_e.id,
        target_job_id: job_f.id,
        condition: :on_job_success
      })

    job_g =
      job_fixture(
        name: "job_g",
        workflow: workflow
      )

    edge_f_g =
      insert(:edge, %{
        workflow: workflow,
        source_job_id: job_f.id,
        target_job_id: job_g.id,
        condition: :on_job_success
      })

    %{
      workflow: workflow,
      project: project,
      edges: %{
        ta: edge_t_a,
        ab: edge_a_b,
        ae: edge_a_e,
        bc: edge_b_c,
        cd: edge_c_d,
        ef: edge_e_f,
        fg: edge_f_g
      },
      jobs: %{
        a: job_a,
        b: job_b,
        c: job_c,
        d: job_d,
        e: job_e,
        f: job_f,
        g: job_g
      }
    }
  end
end
