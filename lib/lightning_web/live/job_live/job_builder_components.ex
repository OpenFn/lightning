defmodule LightningWeb.JobLive.JobBuilderComponents do
  use LightningWeb, :component

  attr :adaptor, :string, required: true
  attr :disabled, :boolean, default: false
  attr :source, :string, required: true
  attr :change_event, :string, default: "job_body_changed"
  attr :rest, :global

  def job_editor_component(assigns) do
    assigns = assigns |> assign(disabled: assigns.disabled |> to_string())

    ~H"""
    <div
      data-adaptor={@adaptor}
      data-source={@source}
      data-disabled={@disabled}
      data-change-event={@change_event}
      phx-hook="JobEditor"
      phx-update="ignore"
      class="flex flex-col h-full"
      {@rest}
    >
      <!-- Placeholder while the component loads -->
      <div>
        <div class="inline-block align-middle ml-2 mr-3 text-indigo-500">
          <svg
            class="animate-spin h-5 w-5"
            xmlns="http://www.w3.org/2000/svg"
            fill="none"
            viewBox="0 0 24 24"
          >
            <circle
              class="opacity-25"
              cx="12"
              cy="12"
              r="10"
              stroke="currentColor"
              stroke-width="4"
            >
            </circle>
            <path
              class="opacity-75"
              fill="currentColor"
              d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
            >
            </path>
          </svg>
        </div>
        <span class="inline-block align-middle">Loading...</span>
      </div>
    </div>
    """
  end
end
