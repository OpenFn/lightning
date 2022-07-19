defmodule LightningWeb.JobLive.InspectorFormComponent do
  @moduledoc """
  Inspector Job Form used on the Workflow Diagram, it's a cut-down version
  of the `BigFormComponent`.

  It uses the `LightningWeb.JobLive.FormComponent` macro for shared functionality.
  """
  use LightningWeb.JobLive.FormComponent

  @impl true
  def save(%{"job" => job_params}, socket) do
    case socket.assigns.action do
      :edit ->
        case Jobs.update_job(socket.assigns.job, job_params) do
          {:ok, _job} ->
            socket
            |> LightningWeb.Components.WorkflowDiagram.push_project_space()
            |> push_patch(to: socket.assigns.return_to)

          {:error, %Ecto.Changeset{} = changeset} ->
            assign(socket, :changeset, changeset)
        end
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"job-#{@id}"}>
      <.form
        let={f}
        for={@changeset}
        id="job-form"
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="grid gap-6">
          <div class="">
            <Form.text_field form={f} id={:name} />
          </div>
          <div class="">
            <Form.check_box form={f} id={:enabled}>
              <p class="text-secondary-500">
                Job will process messages when triggered
              </p>
            </Form.check_box>
          </div>
          <div class="">
            <Components.Jobs.credential_select form={f} credentials={@credentials} />
          </div>
          <div class="">
            <Components.Jobs.adaptor_name_select
              form={f}
              adaptor_name={@adaptor_name}
              adaptors={@adaptors}
            />
          </div>
          <div class="">
            <Components.Jobs.adaptor_version_select
              form={f}
              adaptor_name={@adaptor_name}
              versions={@versions}
            />
          </div>
        </div>
        <Form.divider />
        <.compiler_component adaptor={Phoenix.HTML.Form.input_value(f, :adaptor)} />
        <br />
        <Form.text_area form={f} id={:body} />
        <div class="w-full">
          <Form.submit_button
            value="Save"
            disable_with="Saving"
            changeset={@changeset}
            class="w-full"
          />
        </div>
      </.form>
    </div>
    """
  end

  defp compiler_component(assigns) do
    ~H"""
    <div
      data-adaptor={@adaptor}
      phx-hook="Compiler"
      phx-update="ignore"
      id="compiler-component"
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
