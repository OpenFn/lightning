defmodule LightningWeb.Components.ViewerTest do
  use LightningWeb.ConnCase, async: true

  alias LightningWeb.Components.Viewers

  import Phoenix.LiveViewTest

  import Lightning.Factories

  describe "log_viewer/1" do
    setup do
      [workflow: insert(:simple_workflow)]
    end

    test "renders correct information", %{
      workflow: %{jobs: [job | _rest], project: project}
    } do
      wiped_dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

      finished_step =
        insert(:step,
          job: job,
          input_dataclip: wiped_dataclip,
          output_dataclip: nil,
          finished_at: DateTime.utc_now()
        )

      # finished step for a lost run
      html =
        render_component(&Viewers.log_viewer/1,
          id: "test",
          stream: [],
          stream_empty?: true,
          step: finished_step,
          run_state: :lost,
          dataclip: %Phoenix.LiveView.AsyncResult{
            ok?: false,
            loading: [:input_dataclip]
          },
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: true
        )

      assert html =~ "No logs were received for this run."
      refute html =~ "Nothing yet"
      refute html =~ "data for this step has not been retained"
      refute html =~ "this policy\n      </a>\n      for future runs"
      refute html =~ "test@email.com"
    end
  end

  describe "step_dataclip_viewer/1" do
    setup do
      [workflow: insert(:simple_workflow)]
    end

    test "renders correct information", %{
      workflow: %{jobs: [job | _rest], project: project}
    } do
      wiped_dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

      finished_step =
        insert(:step,
          job: job,
          input_dataclip: wiped_dataclip,
          output_dataclip: nil,
          finished_at: DateTime.utc_now()
        )

      running_step =
        insert(:step,
          job: job,
          input_dataclip: wiped_dataclip,
          finished_at: nil,
          output_dataclip: nil
        )

      # finished step for a lost run
      html =
        render_component(&Viewers.step_dataclip_viewer/1,
          id: "test",
          step: finished_step,
          run_state: :lost,
          dataclip: nil,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: true
        )

      assert html =~ "No input state could be saved for this run."
      refute html =~ "Nothing yet"
      refute html =~ "data for this step has not been retained"
      refute html =~ "this policy\n      </a>\n      for future runs"
      refute html =~ "test@email.com"

      # finished step for a user who can can_edit_data_retention
      html =
        render_component(&Viewers.step_dataclip_viewer/1,
          id: "test",
          step: finished_step,
          run_state: :success,
          dataclip: wiped_dataclip,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: true
        )

      refute html =~ "Nothing yet"
      assert html =~ "data for this step has not been retained"
      assert html =~ "this policy\n      </a>\n      for future runs"
      refute html =~ "test@email.com"

      # finished step for a user who can NOT edit_data_retention
      html =
        render_component(&Viewers.step_dataclip_viewer/1,
          id: "test",
          step: finished_step,
          run_state: :success,
          dataclip: wiped_dataclip,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: false
        )

      refute html =~ "Nothing yet"
      assert html =~ "data for this step has not been retained"
      refute html =~ "this policy\n      </a>\n      for future runs"
      assert html =~ "test@email.com"

      # finished step for a dataclip that was not saved at all
      html =
        render_component(&Viewers.step_dataclip_viewer/1,
          id: "test",
          step: finished_step,
          run_state: :success,
          dataclip: nil,
          input_or_output: :output,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: false
        )

      refute html =~ "Nothing yet"
      assert html =~ "data for this step has not been retained in accordance"

      # running step always shows the pending state
      html =
        render_component(&Viewers.step_dataclip_viewer/1,
          id: "test",
          step: running_step,
          run_state: :pending,
          dataclip: nil,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: true
        )

      assert html =~ "Nothing yet"
      refute html =~ "data for this step has not been retained"
      refute html =~ "this policy\n      </a>\n      for future runs"
      refute html =~ "test@email.com"

      # finished step with dataclip shows the right information
      html =
        render_component(&Viewers.step_dataclip_viewer/1,
          id: "test",
          stream: [],
          stream_empty?: true,
          step: finished_step,
          run_state: :success,
          dataclip: wiped_dataclip,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: true
        )

      refute html =~ "Nothing yet"
      assert html =~ "data for this step has not been retained"
      assert html =~ "this policy\n      </a>\n      for future runs"
      refute html =~ "test@email.com"
    end
  end
end
