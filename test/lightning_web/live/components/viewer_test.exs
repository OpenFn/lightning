defmodule LightningWeb.Components.ViewerTest do
  use LightningWeb.ConnCase, async: true

  alias LightningWeb.Components.Viewers

  import Phoenix.LiveViewTest

  import Lightning.Factories

  describe "dataclip_viewer/1" do
    setup do
      [workflow: insert(:simple_workflow)]
    end

    test "renders correct information for a wiped dataclip", %{
      workflow: %{jobs: [job | _rest], project: project}
    } do
      dataclip = insert(:dataclip, body: nil, wiped_at: DateTime.utc_now())

      finished_step =
        insert(:step,
          job: job,
          input_dataclip: dataclip,
          finished_at: DateTime.utc_now()
        )

      running_step =
        insert(:step, job: job, input_dataclip: dataclip, finished_at: nil)

      # finished step for a user who can can_edit_data_retention
      html =
        render_component(&Viewers.dataclip_viewer/1,
          id: "test",
          stream: [],
          step: finished_step,
          dataclip: dataclip,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: true
        )

      refute html =~ "Nothing yet"
      assert html =~ "No input data has been saved here in accordance"
      assert html =~ "Go to retention settings"
      refute html =~ "test@email.com"

      # finished step for a user who can NOT edit_data_retention
      html =
        render_component(&Viewers.dataclip_viewer/1,
          id: "test",
          stream: [],
          step: finished_step,
          dataclip: dataclip,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: false
        )

      refute html =~ "Nothing yet"
      assert html =~ "No input data has been saved here in accordance"
      refute html =~ "Go to retention settings"
      assert html =~ "test@email.com"

      # finished step for a dataclip that was not saved at all
      html =
        render_component(&Viewers.dataclip_viewer/1,
          id: "test",
          stream: [],
          step: finished_step,
          dataclip: nil,
          input_or_output: :output,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: false
        )

      refute html =~ "Nothing yet"
      assert html =~ "No output data has been saved here in accordance"

      # running step always shows the pending state
      html =
        render_component(&Viewers.dataclip_viewer/1,
          id: "test",
          stream: [],
          step: running_step,
          dataclip: dataclip,
          input_or_output: :input,
          project_id: project.id,
          admin_contacts: ["test@email.com"],
          can_edit_data_retention: true
        )

      assert html =~ "Nothing yet"
      refute html =~ "No input data has been saved here in accordance"
      refute html =~ "Go to retention settings"
      refute html =~ "test@email.com"
    end
  end
end
