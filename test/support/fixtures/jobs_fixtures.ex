defmodule Lightning.JobsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Jobs` context.
  """

  import Lightning.ProjectsFixtures
  import Lightning.WorkflowsFixtures
  import Lightning.Factories

  @doc """
  Generate a job.
  """
  @spec job_fixture(attrs :: Keyword.t()) :: Lightning.Workflows.Job.t()
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
      |> Lightning.Jobs.create_job(insert(:user))

    job
  end

  defp random_name do
    suffix =
      Ecto.UUID.generate() |> String.split_at(5) |> then(fn {x, _} -> x end)

    "Untitled-#{suffix}"
  end

  def workflow_job_fixture(attrs \\ []) do
    {workflow_name, attrs} =
      attrs |> Enum.into(%{}) |> Map.pop(:workflow_name, random_name())

    attrs =
      attrs
      |> case do
        %{project: _project} ->
          attrs

        # Here as a stop gap while we change all the call sites
        attrs = %{project_id: project_id} ->
          attrs
          |> Map.drop([:project_id])
          |> Map.put_new(
            :project,
            Lightning.Repo.get!(Lightning.Projects.Project, project_id)
          )

        attrs ->
          attrs |> Map.put_new(:project, insert(:project))
      end

    workflow =
      insert(
        :workflow,
        %{
          name: workflow_name,
          project: attrs[:project]
        }
      )

    project_credential =
      attrs[:project_credential] ||
        insert(:project_credential,
          credential: %{
            name: "my first cred",
            body: %{"shhh" => "secret-stuff"}
          },
          project: attrs[:project]
        )

    attrs =
      attrs
      |> Enum.into(%{
        body: "fn(state => state)",
        name: "some name",
        adaptor: "@openfn/language-common",
        workflow: workflow,
        project_credential: project_credential
      })

    job = insert(:job, attrs)

    t =
      insert(:trigger,
        workflow: attrs[:workflow],
        type: :webhook,
        enabled: true
      )

    e =
      insert(:edge,
        workflow: attrs[:workflow],
        source_trigger: t,
        target_job: job,
        condition_type: :always,
        enabled: true
      )

    %{job: job, edge: e, trigger: t, workflow: workflow}
  end

  @deprecated "Use the `:complex_workflow` factory instead"
  def workflow_scenario(context \\ %{}) do
    project = Map.get_lazy(context, :project, fn -> insert(:project) end)
    workflow = insert(:workflow, project: project)

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

    job_a = insert(:job, %{name: "job_a", workflow: workflow})

    edge_t_a =
      insert(:edge, %{
        workflow: workflow,
        source_trigger: trigger,
        target_job: job_a
      })

    job_b = insert(:job, %{name: "job_b", workflow: workflow})

    edge_a_b =
      insert(:edge, %{
        workflow: workflow,
        source_job: job_a,
        target_job: job_b,
        condition_type: :on_job_success
      })

    job_c = insert(:job, %{name: "job_c", workflow: workflow})

    edge_b_c =
      insert(:edge, %{
        workflow: workflow,
        source_job: job_b,
        target_job: job_c,
        condition_type: :on_job_success
      })

    job_d = insert(:job, %{name: "job_d", workflow: workflow})

    edge_c_d =
      insert(:edge, %{
        workflow: workflow,
        source_job: job_c,
        target_job: job_d,
        condition_type: :on_job_success
      })

    job_e = insert(:job, %{name: "job_e", workflow: workflow})

    edge_a_e =
      insert(:edge, %{
        workflow: workflow,
        source_job: job_a,
        target_job: job_e,
        condition_type: :on_job_success
      })

    job_f = insert(:job, %{name: "job_f", workflow: workflow})

    edge_e_f =
      insert(:edge, %{
        workflow: workflow,
        source_job: job_e,
        target_job: job_f,
        condition_type: :on_job_success
      })

    job_g = insert(:job, %{workflow: workflow, name: "job_g"})

    edge_f_g =
      insert(:edge, %{
        workflow: workflow,
        source_job: job_f,
        target_job: job_g,
        condition_type: :on_job_success
      })

    %{
      workflow: workflow |> Lightning.Repo.reload(),
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
