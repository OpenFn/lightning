defmodule Lightning.RunLive.Components do
  use LightningWeb, :component

  import LightningWeb.Components.Form

  @spec workflow_select(any) :: Phoenix.LiveView.Rendered.t()
  def workflow_select(assigns) do
    ~H"""
    <div>
      <div class="font-semibold mt-4 mb-2">Filter by workflow</div>
      <%= error_tag(@form, :workflow_id, class: "block w-full rounded-md") %>
      <.select_field
        form={@form}
        name={:workflow_id}
        id="workflowField"
        prompt="Show all"
        values={@values}
      />
    </div>
    """
  end
end
