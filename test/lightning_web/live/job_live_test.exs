defmodule LightningWeb.JobLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.JobsFixtures
  import Lightning.CredentialsFixtures
  import Lightning.WorkflowsFixtures
  import SweetXml

  alias LightningWeb.JobLive.AdaptorPicker

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    project_credential_fixture(project_id: project.id)
    %{job: job} = workflow_job_fixture(project_id: project.id)
    %{job: job}
  end

  describe "The adaptor picker" do
    test "abbreviates standard adaptors via display_name_for_adaptor/1" do
      assert AdaptorPicker.display_name_for_adaptor("@openfn/language-abc") ==
               {"abc", "@openfn/language-abc"}

      assert AdaptorPicker.display_name_for_adaptor("@openfn/adaptor-xyz") ==
               "@openfn/adaptor-xyz"

      assert AdaptorPicker.display_name_for_adaptor("@other_org/some_module") ==
               "@other_org/some_module"
    end
  end

  describe "Show tooltip" do
    @describetag skip: true
    def tooltip_text(element) do
      element
      |> render()
      |> parse()
      |> xpath(~x"@aria-label"l)
      |> to_string()
    end

    test "should display tooltip", %{
      conn: conn,
      project: project
    } do
      workflow = workflow_fixture(name: "the workflow", project_id: project.id)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}?step=1&j=1"
        )

      # Trigger tooltip
      assert view
             |> element("#trigger-tooltip")
             |> tooltip_text() ==
               "Choose when this job should run. Select 'webhook' for realtime workflows triggered by notifications from external systems."

      # Adaptor tooltip
      assert view
             |> element("#adaptor_name-tooltip")
             |> tooltip_text() ==
               "Choose an adaptor to perform operations (via helper functions) in a specific application. Pick ‘http’ for generic REST APIs or the 'common' adaptor if this job only performs data manipulation."

      # Credential tooltip
      assert view
             |> element("#project_credential_id-tooltip")
             |> tooltip_text() ==
               "If the system you're working with requires authentication, choose a credential with login details (secrets) that will allow this job to connect. If you're not connecting to an external system you don't need a credential."
    end
  end
end
