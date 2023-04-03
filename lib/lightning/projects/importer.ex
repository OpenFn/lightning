defmodule Lightning.Projects.Importer do
  @moduledoc """
  Module that expose a function building a multi for importing a project yaml (via a map)
  """

  import Ecto.Changeset

  alias Ecto.Multi

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Workflow
  alias Lightning.Credentials.Credential
  alias Lightning.Jobs.Job

  def import_multi_for_project(project_data, user) do
    project_data = project_data |> Lightning.Helpers.stringify_keys()

    Multi.new()
    |> put_project(project_data, user)
    |> put_credentials(project_data, user)
    |> put_workflows(project_data)
  end

  defp put_project(multi, project_data, user) do
    multi
    |> Multi.insert(:project, fn _ ->
      id = Ecto.UUID.generate()

      attrs =
        project_data
        |> Map.merge(%{"id" => id, "project_users" => [%{"user_id" => user.id}]})

      %Project{}
      |> Project.changeset(attrs)
    end)
  end

  def import_workflow_changeset(
        workflow,
        %{workflow_id: workflow_id, project_id: project_id},
        import_transaction
      ) do
    workflow =
      Map.merge(workflow, %{
        "id" => workflow_id,
        "project_id" => project_id
      })

    %Workflow{}
    |> cast(workflow, [:name, :project_id, :id])
    |> cast_assoc(:jobs,
      with:
        {__MODULE__, :import_job_changeset, [workflow_id, import_transaction]}
    )
  end

  def import_job_changeset(job, attrs, workflow_id, import_transaction) do
    credential_key = attrs["credential"]

    attrs = Map.merge(attrs, %{"workflow_id" => workflow_id})

    if credential_key do
      credential = import_transaction["credential::#{credential_key}"]

      if credential do
        %{project_credentials: [%{id: project_credential_id}]} = credential

        attrs =
          Map.merge(attrs, %{"project_credential_id" => project_credential_id})

        job
        |> Job.changeset(attrs, workflow_id)
      else
        job
        |> Job.changeset(attrs, workflow_id)
        |> add_error(:credential, "not found in project input")
      end
    else
      job
      |> Job.changeset(attrs, workflow_id)
    end
  end

  defp put_workflows(multi, project_data) do
    workflows = project_data["workflows"] || []

    workflows
    |> Enum.reduce(multi, fn workflow, m ->
      workflow_id = Ecto.UUID.generate()

      Multi.insert(m, "workflow::#{workflow_id}", fn %{project: project} =
                                                       import_transaction ->
        import_workflow_changeset(
          workflow,
          %{workflow_id: workflow_id, project_id: project.id},
          import_transaction
        )
      end)
    end)
  end

  defp put_credentials(multi, project_data, user) do
    credentials = project_data["credentials"] || []

    credentials
    |> Enum.reduce(multi, fn credential, m ->
      Multi.insert(m, "credential::#{credential["key"]}", fn %{
                                                               project: project
                                                             } ->
        id = Ecto.UUID.generate()

        attrs =
          Map.merge(
            credential,
            %{
              "id" => id,
              "user_id" => user.id,
              "project_credentials" => [
                %{
                  "project_id" => project.id,
                  "credential_id" => id
                }
              ]
            }
          )

        %Credential{}
        |> Credential.changeset(attrs)
      end)
    end)
  end
end
