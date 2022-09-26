defmodule Lightning.SetupDemo do
  alias Lightning.{Projects, Accounts, Jobs, Workflows}

  def create_data do
    {:ok, openhie_admin} =
      Accounts.register_user(%{
        first_name: "openhie_admin",
        last_name: "admin",
        email: "openhie_admin@gmail.com",
        password: "openhie_admin123"
      })

    {:ok, openhie_editor} =
      Accounts.register_user(%{
        first_name: "openhie_editor",
        last_name: "editor",
        email: "openhie_editor@gmail.com",
        password: "openhie_editor123"
      })

    {:ok, openhie_viewer} =
      Accounts.register_user(%{
        first_name: "openhie_viewer",
        last_name: "viewer",
        email: "openhie_viewer@gmail.com",
        password: "openhie_viewer123"
      })

    {:ok, openhie_project} =
      Projects.create_project(%{
        name: "openhie-demo-project",
        project_users: [
          %{user_id: openhie_admin.id},
          %{user_id: openhie_editor.id},
          %{user_id: openhie_viewer.id}
        ]
      })

    {:ok, dhis2_project} =
      Projects.create_project(%{name: "dhis2-demo-project", project_users: []})

    {:ok, openhie_workflow} =
      Workflows.create_workflow(%{
        name: "OpenHIE demo workflow",
        project_id: openhie_project.id
      })

    {:ok, fhir_standard_data} =
      Jobs.create_job(%{
        name: "Transform data to FHIR standard",
        body: "fn(state => state)",
        adaptor: "@openfn/language-http",
        trigger: %{type: "webhook"},
        project_id: openhie_project.id,
        workflow_id: openhie_workflow.id
      })

    {:ok, send_to_openhim} =
      Jobs.create_job(%{
        name: "Send to OpenHIM to route to SHR",
        body: "fn(state => state)",
        adaptor: "@openfn/language-http",
        trigger: %{
          type: "on_job_success",
          upstream_job_id: fhir_standard_data.id
        },
        project_id: openhie_project.id
      })

    {:ok, notify_upload_successful} =
      Jobs.create_job(%{
        name: "Notify CHW upload successful",
        body: "fn(state => state)",
        adaptor: "@openfn/language-http",
        trigger: %{type: "on_job_success", upstream_job_id: send_to_openhim.id},
        project_id: openhie_project.id
      })

    {:ok, notify_upload_failed} =
      Jobs.create_job(%{
        name: "Notify CHW upload failed",
        body: "fn(state => state)",
        adaptor: "@openfn/language-http",
        trigger: %{type: "on_job_failure", upstream_job_id: send_to_openhim.id},
        project_id: openhie_project.id
      })

    {:ok, dhis2_workflow} =
      Workflows.create_workflow(%{
        name: "Load DHIS2 data to sheets",
        project_id: dhis2_project.id
      })

    {:ok, get_dhis2_data} =
      Jobs.create_job(%{
        name: "Get DHIS2 data",
        body: "fn(state => state)",
        adaptor: "@openfn/language-dhis2",
        trigger: %{type: "cron", cron_expression: "0 * * * *"},
        project_id: dhis2_project.id,
        workflow_id: dhis2_workflow.id
      })

    {:ok, upload_to_google_sheet} =
      Jobs.create_job(%{
        name: "Upload to google sheet",
        body: "fn(state => state)",
        adaptor: "@openfn/language-http",
        trigger: %{type: "on_job_success", upstream_job_id: get_dhis2_data.id},
        project_id: dhis2_project.id
      })

    %{
      users: [openhie_admin, openhie_editor, openhie_viewer],
      projects: [openhie_project, dhis2_project],
      workflows: [openhie_workflow, dhis2_workflow],
      jobs: [
        fhir_standard_data,
        send_to_openhim,
        notify_upload_successful,
        notify_upload_failed,
        get_dhis2_data,
        upload_to_google_sheet
      ]
    }
  end
end
