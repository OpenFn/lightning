defmodule LightningWeb.JobLive.JobBuilderComponents do
  use LightningWeb, :component

  import React

  attr :adaptor, :string, required: true
  attr :disabled, :boolean, default: false
  attr :disabled_message, :string, required: true
  attr :job_id, :string, required: true
  attr :source, :string, required: true
  attr :rest, :global

  jsx("assets/js/job-editor/JobEditor.tsx")

  def job_editor_component(assigns) do
    assigns = assigns |> assign(disabled: assigns.disabled |> to_string())

    ~H"""
    <.JobEditor
      job_id={@job_id}
      adaptor={@adaptor}
      source={@source}
      disabled={@disabled}
      disabled_message={@disabled_message}
      class="flex flex-col h-full"
    />
    """
  end
end
