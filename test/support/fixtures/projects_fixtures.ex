defmodule Lightning.ProjectsFixtures do
  @moduledoc """
  This module defines test helpers for creating
  entities via the `Lightning.Projects` context.
  """

  alias Lightning.Factories

  @doc """
  Generate a project.
  """
  @spec project_fixture(attrs :: Keyword.t()) :: Lightning.Projects.Project.t()
  def project_fixture(attrs \\ []) when is_list(attrs) do
    attrs =
      Enum.into(attrs, %{
        name: "a-test-project",
        project_users: []
      })

    Factories.insert(:project, attrs)
  end

  def build_full_project(attrs \\ %{}) do
    user =
      if attrs[:owner] do
        attrs[:owner]
      else
        Factories.insert(:user,
          email: ExMachina.sequence(:email, &"email-#{&1}@example.com")
        )
      end

    # There's no :owner key in a project, but this shortcut is useful for
    # building the canonical project for testing the provisioning API.
    attrs = Keyword.delete(attrs, :owner)

    credential =
      Factories.insert(:credential,
        user: user,
        name: "new credential",
        body: %{"foo" => "super-secret"}
      )

    project_credential =
      Factories.build(:project_credential,
        id: Ecto.UUID.generate(),
        credential: credential,
        project: nil
      )

    workflow_1_trigger = Factories.build(:trigger)

    workflow_1_job_1 =
      Factories.build(:job,
        name: "webhook job",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: DateTime.utc_now() |> Timex.shift(seconds: 0),
        body: "console.log('webhook job')\nfn(state => state)",
        project_credential_id: project_credential.id
      )

    workflow_1_job_2 =
      Factories.build(:job,
        name: "on fail",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: DateTime.utc_now() |> Timex.shift(seconds: 1),
        body: "console.log('on fail')\nfn(state => state)"
      )

    workflow_1_job_3 =
      Factories.build(:job,
        name: "on success",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: DateTime.utc_now() |> Timex.shift(seconds: 2)
      )

    workflow_1 =
      Factories.build(:workflow, name: "workflow 1", project: nil)
      |> Factories.with_trigger(workflow_1_trigger)
      |> Factories.with_job(workflow_1_job_1)
      |> Factories.with_job(workflow_1_job_2)
      |> Factories.with_job(workflow_1_job_3)
      |> Factories.with_edge({workflow_1_trigger, workflow_1_job_1},
        condition_type: :always
      )
      |> Factories.with_edge({workflow_1_job_1, workflow_1_job_2},
        condition_type: :on_job_failure
      )
      |> Factories.with_edge({workflow_1_job_1, workflow_1_job_3},
        condition_type: :on_job_success
      )

    workflow_2_trigger =
      Factories.build(:trigger,
        type: :cron,
        cron_expression: "0 23 * * *"
      )

    workflow_2_job_1 =
      Factories.build(:job,
        name: "some cronjob",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: DateTime.utc_now() |> Timex.shift(seconds: 3)
      )

    workflow_2_job_2 =
      Factories.build(:job,
        name: "on cron failure",
        # Note: we can drop inserted_at once there's a reliable way to sort yaml for export
        inserted_at: DateTime.utc_now() |> Timex.shift(seconds: 4)
      )

    workflow_2 =
      Factories.build(:workflow, name: "workflow 2", project: nil)
      |> Factories.with_trigger(workflow_2_trigger)
      |> Factories.with_job(workflow_2_job_1)
      |> Factories.with_job(workflow_2_job_2)
      |> Factories.with_edge({workflow_2_trigger, workflow_2_job_1},
        condition_type: :always
      )
      |> Factories.with_edge({workflow_2_job_1, workflow_2_job_2},
        condition_type: :on_job_success
      )

    Factories.build(:project,
      name: "a-test-project",
      description: "This is only a test",
      project_credentials: [project_credential],
      workflows: [workflow_1, workflow_2],
      project_users: [%{user: user}]
    )
    |> ExMachina.merge_attributes(attrs)
    |> Factories.insert()
    |> then(fn %{workflows: [workflow_1, workflow_2]} = project ->
      project_credential = Lightning.Repo.reload(project_credential)

      workflow_1_job_1 =
        workflow_1_job_1
        |> Lightning.Repo.reload()
        |> Lightning.Repo.preload(:project_credential)
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.put_assoc(:project_credential, project_credential)
        |> Lightning.Repo.update!()

      workflow_1_jobs =
        Enum.reduce(workflow_1.jobs, [], fn job, acc ->
          if job.id == workflow_1_job_1.id do
            acc ++ [workflow_1_job_1]
          else
            acc ++ [job]
          end
        end)

      %{project | workflows: [%{workflow_1 | jobs: workflow_1_jobs}, workflow_2]}
    end)
  end

  @doc """
  This is a variant of a "full project" that's used specifically to test the
  provisioning API. It's owned by and created by the
  "cannonical-user@lightning.com" and there can only be one in the DB at any
  given time.
  """
  def canonical_project_fixture(attrs \\ []) do
    attrs =
      attrs
      |> Keyword.put_new_lazy(:owner, fn ->
        Factories.insert(:user, email: "cannonical-user@lightning.com")
      end)

    build_full_project(attrs)
  end
end
