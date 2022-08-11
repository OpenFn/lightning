defmodule LightningWeb.JobLive.InspectorFormComponent do
  @moduledoc """
  Form Component for working with a single Job.

  A Job's `adaptor` field is a combination of the module name and the version.
  It's formatted as an NPM style string.

  The form allows the user to select a module by name and then it's version,
  while the version dropdown itself references `adaptor` directly.

  Meaning the `adaptor_name` dropdown and assigns value is not persisted.

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
            |> put_flash(:info, "Job updated successfully")
            |> LightningWeb.Components.WorkflowDiagram.push_project_space()
            |> push_redirect(to: socket.assigns.return_to)

          {:error, %Ecto.Changeset{} = changeset} ->
            assign(socket, :changeset, changeset)
        end

      :new ->
        case Jobs.create_job(
               job_params
               |> Map.put("project_id", socket.assigns.job.project_id)
             ) do
          {:ok, _job} ->
            socket
            |> put_flash(:info, "Job created successfully")
            |> push_redirect(to: socket.assigns.return_to)

          {:error, %Ecto.Changeset{} = changeset} ->
            assign(socket, changeset: changeset)
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
        <div class="md:grid md:grid-cols-2 md:gap-4">
          <div class="md:col-span-1">
            <Form.text_field form={f} id={:name} />
          </div>
          <div class="md:col-span-1">
            <Form.check_box form={f} id={:enabled} />
          </div>

          <div class="md:col-span-1">
            <%= inputs_for f, :trigger, fn ft -> %>
              <%= label ft, :type, class: "block" do %>
                <span class="block text-sm font-medium text-secondary-700">
                  Trigger
                </span>
                <%= error_tag(ft, :type, class: "block w-full rounded-md") %>
                <Form.select_field
                  form={ft}
                  name={:type}
                  prompt=""
                  id="triggerType"
                  values={
                    [
                      Cron: "cron",
                      Webhook: "webhook",
                      "On Job Success": "on_job_success",
                      "On Job Failure": "on_job_failure"
                    ]
                  }
                />
              <% end %>

              <%= if ft.data.id && ft.data.job_id do %>
                <a
                  id="copyWebhookUrl"
                  href={Routes.webhooks_url(@socket, :create, [ft.data.job_id])}
                  onclick="(function(e) {  navigator.clipboard.writeText(e.target.href); e.preventDefault(); })(event)"
                  target="_blank"
                >
                  Copy webhook url
                </a>
              <% end %>

              <%= if requires_upstream_job?(ft.source) do %>
                <%= label ft, :upstream_job_id, class: "block" do %>
                  <span class="block text-sm font-medium text-secondary-700">
                    Upstream Job
                  </span>
                  <%= error_tag(ft, :upstream_job_id,
                    class: "block w-full rounded-md"
                  ) %>
                  <Form.select_field
                    form={ft}
                    name={:upstream_job_id}
                    prompt=""
                    id="upstreamJob"
                    values={Enum.map(@upstream_jobs, &{&1.name, &1.id})}
                  />
                <% end %>
              <% end %>
              <%= if requires_cron_job?(ft.source) do %>
                <Form.text_field form={ft} id={:cron_expression} />
              <% end %>
            <% end %>
          </div>

          <div class="md:col-span-1">
            <Components.Jobs.credential_select form={f} credentials={@credentials} />
          </div>

          <div class="md:col-span-1">
            <Components.Jobs.adaptor_name_select
              form={f}
              adaptor_name={@adaptor_name}
              adaptors={@adaptors}
            />
          </div>

          <div class="md:col-span-1">
            <Components.Jobs.adaptor_version_select
              form={f}
              adaptor_name={@adaptor_name}
              versions={@versions}
            />
          </div>
        </div>
        <Form.divider />
        <div class="md:grid md:grid-cols-2 md:gap-4">
          <div class="md:col-span-2">
            <.compiler_component adaptor={Phoenix.HTML.Form.input_value(f, :adaptor)} />
          </div>
          <div class="md:col-span-2">
            <div
              phx-hook="Editor"
              phx-update="ignore"
              data-source={f.data.body}
              id="editor-component"
            >
              <!--placeholder -->
              <h2>loading</h2>
            </div>
          </div>
          <div class="md:col-span-2 w-full">
            <span>
              <%= live_redirect("Cancel",
                class:
                  "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500",
                to: Routes.project_dashboard_index_path(@socket, :show, @project.id)
              ) %>
            </span>
            <Form.submit_button
              value="Save"
              disable_with="Saving"
              changeset={@changeset}
            />
          </div>
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
