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
              <p class="text-gray-500">Job will process messages when triggered</p>
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
end
