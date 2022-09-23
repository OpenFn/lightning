# Script for populating the database. You can run it as:
#
#     mix run priv/repo/setup_demo.exs
#
# When I set up a new implementation of Lightning using docker, I would like to pre-populate
# my instance with some existing data (jobs, credentials, and users) so that I can start trying it immediately.

{:ok, openhie_admin} = Lightning.Accounts.register_user(%{
  first_name: "openhie_admin",
  last_name: "admin",
  email: "openhie_admin@gmail.com",
  password: "openhie_admin123"
})
{:ok, openhie_editor} = Lightning.Accounts.register_user(%{
  first_name: "openhie_editor",
  last_name: "editor",
  email: "openhie_editor@gmail.com",
  password: "openhie_editor123"
})
{:ok, openhie_viewer} = Lightning.Accounts.register_user(%{
  first_name: "openhie_viewer",
  last_name: "viewer",
  email: "openhie_viewer@gmail.com",
  password: "openhie_viewer123"
})


{:ok, openhie_project} = Lightning.Projects.create_project(%{
  name: "openhie-demo-project",
  project_users: [
    %{user_id: openhie_admin.id},
    %{user_id: openhie_editor.id},
    %{user_id: openhie_viewer.id}
  ]
})

{:ok, dhis2_project} = Lightning.Projects.create_project(%{name: "dhis2-demo-project"})

{:ok, openhie_workflow} = Lightning.Workflows.create_workflow(%{
  name: "OpenHIE demo workflow",
  project_id: openhie_project.id
})
{:ok, fhir_standard_data} =
  Lightning.Jobs.create_job(%{
    name: "Transform data to FHIR standard",
    body: "fn(state => state)",
    adaptor: "@openfn/language-http",
    trigger: %{type: "webhook"},
    project_id: openhie_project.id,
    workflow_id: openhie_workflow.id
  })
{:ok, send_to_openhim} =
  Lightning.Jobs.create_job(%{
    name: "Send to OpenHIM to route to SHR",
    body: "fn(state => state)",
    adaptor: "@openfn/language-http",
    trigger: %{type: "on_job_success", upstream_job_id: fhir_standard_data.id},
    project_id: openhie_project.id
  })
{:ok, _notify_upload_successful} =
  Lightning.Jobs.create_job(%{
    name: "Notify CHW upload successful",
    body: "fn(state => state)",
    adaptor: "@openfn/language-http",
    trigger: %{type: "on_job_success", upstream_job_id: send_to_openhim.id},
    project_id: openhie_project.id
  })
{:ok, _notify_upload_failed} =
  Lightning.Jobs.create_job(%{
    name: "Notify CHW upload failed",
    body: "fn(state => state)",
    adaptor: "@openfn/language-http",
    trigger: %{type: "on_job_failure", upstream_job_id: send_to_openhim.id},
    project_id: openhie_project.id
  })

{:ok, dhis2_workflow} = Lightning.Workflows.create_workflow(%{
  name: "Load DHIS2 data to sheets",
  project_id: dhis2_project.id
})
{:ok, get_dhis2_data} =
  Lightning.Jobs.create_job(%{
    name: "Get DHIS2 data",
    body: "fn(state => state)",
    adaptor: "@openfn/language-dhis2",
    trigger: %{type: "cron", cron_expression: "0 * * * *"},
    project_id: dhis2_project.id,
    workflow_id: dhis2_workflow.id
  })
{:ok, _upload_to_google_sheet} =
  Lightning.Jobs.create_job(%{
    name: "Upload to google sheet",
    body: "fn(state => state)",
    adaptor: "@openfn/language-http",
    trigger: %{type: "on_job_success", upstream_job_id: get_dhis2_data.id},
    project_id: dhis2_project.id
  })
