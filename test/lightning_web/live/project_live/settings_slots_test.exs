defmodule LightningWeb.SlotEchoComponent do
  @moduledoc false
  use Phoenix.LiveComponent

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> Map.put_new(:current_user, nil)
      |> Map.put_new(:disabled, nil)

    ~H"""
    <div
      id={@id}
      data-project-id={@project.id}
      data-current-user-id={if @current_user, do: @current_user.id, else: ""}
      data-disabled={if is_nil(@disabled), do: "", else: "#{@disabled}"}
    >
      echo
    </div>
    """
  end
end

defmodule LightningWeb.ProjectLive.SettingsSlotsTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias LightningWeb.ProjectLive.Settings

  describe "concurrency_input_slot/1" do
    test "forwards project, field, and disabled to the registered component" do
      project = insert(:project)
      changeset = Lightning.Projects.Project.changeset(project, %{})
      form = Phoenix.HTML.FormData.to_form(changeset, [])

      html =
        render_component(
          &Settings.concurrency_input_slot/1,
          component: LightningWeb.SlotEchoComponent,
          field: form[:concurrency],
          project: project,
          disabled: true
        )

      assert html =~ ~s(data-project-id="#{project.id}")
      assert html =~ ~s(data-disabled="true")
    end
  end

  describe "usage_caps_input_slot/1" do
    test "forwards project and current_user to the registered component" do
      project = insert(:project)
      user = insert(:user)

      html =
        render_component(
          &Settings.usage_caps_input_slot/1,
          component: LightningWeb.SlotEchoComponent,
          project: project,
          current_user: user
        )

      assert html =~ ~s(data-project-id="#{project.id}")
      assert html =~ ~s(data-current-user-id="#{user.id}")
    end
  end
end
