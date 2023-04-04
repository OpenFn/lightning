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
    project_data =
      project_data
      |> Lightning.Helpers.stringify_keys()

    # TODO: ensure all entities have a `key` key that is unique across the whole document

    Multi.new()
    |> put_project(project_data, user)
    |> put_credentials(project_data, user)
    |> put_workflows(project_data)
    |> put_jobs(project_data)
  end

  defp put_project(multi, project_data, user) do
    multi
    |> Multi.run(:project, fn repo, _ ->
      attrs =
        project_data
        |> Map.merge(%{"project_users" => [%{"user_id" => user.id}]})

      project_id = project_data["id"]

      project =
        if project_id do
          repo.get(Project, project_id)
        end || %Project{}

      repo.insert_or_update(Project.changeset(project, attrs))
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
    |> Enum.reduce(multi, fn workflow_params, m ->
      Multi.run(
        m,
        workflow_params["key"],
        fn repo, %{project: project} ->
          {params, workflow} =
            case workflow_params do
              %{"id" => id} = params when not is_nil(id) ->
                {
                  Map.merge(params, %{"project_id" => project.id}),
                  repo.get(Workflow, id) || %Workflow{}
                }

              params ->
                {
                  Map.merge(params, %{
                    "project_id" => project.id,
                    "id" => Ecto.UUID.generate()
                  }),
                  %Workflow{}
                }
            end

          changeset =
            workflow
            |> Workflow.changeset(
              params
              |> Map.reject(fn {k, _} -> k in ["jobs"] end)
            )

          repo.insert_or_update(changeset)

          # import_workflow_changeset(
          #   workflow,
          #   %{workflow_id: workflow_id, project_id: project.id},
          #   import_transaction
          # )
        end
      )
    end)
  end

  def put_jobs(multi, project_data) do
    Map.get(project_data, "workflows", [])
    |> Enum.reduce(multi, fn workflow, multi ->
      workflow
      |> Map.get("jobs", [])
      |> Enum.reduce(multi, fn job, multi ->
        multi
        |> Multi.insert(job["key"], fn items ->
          workflow = Map.get(items, workflow["key"])

          %Job{}
          |> Job.changeset(job |> Map.put("workflow_id", workflow.id))
        end)
      end)
    end)
  end

  defp put_credentials(multi, project_data, user) do
    credentials = project_data["credentials"] || []

    credentials
    |> Enum.reduce(multi, fn credential, m ->
      Multi.insert(m, credential["key"], fn %{
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
