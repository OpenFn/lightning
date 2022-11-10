defmodule Lightning.RunLive.Components do
  use LightningWeb, :component

  import LightningWeb.Components.Form

  def workflow_select(assigns) do
    ~H"""
    <.label_field
      form={@form}
      id={:workflow_id}
      title="Workflow"
      for="workflowField"
    />
    <%= error_tag(@form, :workflow_id, class: "block w-full rounded-md") %>
    <.select_field
      form={@form}
      name={:workflow_id}
      id="workflowField"
      prompt=""
      values={@workflows}
    />
    """
  end
end
