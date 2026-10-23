defmodule LightningWeb.API.ProvisioningHelpers do
  @moduledoc false

  def put_bearer(conn, token) do
    Plug.Conn.put_req_header(conn, "authorization", "Bearer #{token}")
  end

  def reenable_triggers_payload(project, workflow) do
    [job] = workflow.jobs
    [trigger] = workflow.triggers
    [edge] = workflow.edges

    %{
      "id" => project.id,
      "name" => project.name,
      "workflows" => [
        %{
          "id" => workflow.id,
          "name" => workflow.name,
          "jobs" => [
            %{
              "id" => job.id,
              "name" => job.name,
              "adaptor" => job.adaptor,
              "body" => job.body
            }
          ],
          "triggers" => [
            %{"id" => trigger.id, "type" => "webhook", "enabled" => true}
          ],
          "edges" => [
            %{
              "id" => edge.id,
              "source_trigger_id" => trigger.id,
              "target_job_id" => job.id,
              "condition_type" => "always",
              "enabled" => true
            }
          ]
        }
      ]
    }
  end

  def valid_payload(project_id \\ nil) do
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
              "condition_type" => "on_job_success",
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

  def add_job_to_document(document, job_params) do
    update_in(document, ["workflows", Access.at(0), "jobs"], &[job_params | &1])
  end

  def remove_job_from_document(document, id) do
    update_in(document, ["workflows", Access.at(0), "jobs"], fn jobs ->
      Enum.map(jobs, fn
        %{"id" => ^id} = job -> Map.put(job, "delete", true)
        job -> job
      end)
    end)
  end
end
