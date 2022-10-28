defmodule LightningWeb.JobLive.SetupFormComponent do
  @moduledoc """
  SetupFormComponent
  """

  use LightningWeb, :live_component

  import Ecto.Changeset, only: [get_field: 2]

  import Phoenix.LiveView,
    only: [assign: 2, assign: 3]

  alias Lightning.{Jobs, AdaptorRegistry, Projects}
  alias LightningWeb.Components.Form
  alias Jobs.JobForm

  def update(
        %{
          job_form: job_form,
          project: project,
          initial_job_params: initial_job_params
        } = assigns,
        socket
      ) do
    changeset = JobForm.changeset(job_form, initial_job_params)

    {adaptor_name, _, adaptors, versions} =
      get_adaptor_version_options(
        changeset
        |> Ecto.Changeset.fetch_field!(:adaptor)
      )

    credentials =
      Projects.list_project_credentials(project)
      |> Enum.map(fn pu ->
        {pu.credential.name, pu.id}
      end)

    upstream_jobs = Jobs.get_upstream_jobs_for(job_form)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:adaptor_name, adaptor_name)
     |> assign(:adaptors, adaptors)
     |> assign(:credentials, credentials)
     |> assign(:upstream_jobs, upstream_jobs)
     |> assign(:versions, versions)
     |> assign(:job_form, job_form)
     |> assign(:changeset, changeset)
     |> assign(:job_params, %{})}
  end

  def validate(%{"job_form" => job_params}, socket) do
    job_params = coerce_params_for_adaptor_list(job_params)

    changeset =
      JobForm.changeset(socket.assigns.job_form, job_params)
      |> Map.put(:action, :validate)

    {adaptor_name, _, adaptors, versions} =
      get_adaptor_version_options(
        changeset
        |> Ecto.Changeset.fetch_field!(:adaptor)
      )

    assign(socket, :changeset, changeset)
    |> assign(:adaptor_name, adaptor_name)
    |> assign(:adaptors, adaptors)
    |> assign(:versions, versions)
    |> assign(:job_params, job_params)
  end

  def get_adaptor_version_options(adaptor) do
    # Gets @openfn/language-foo@1.2.3 or @openfn/language-foo

    adaptor_names =
      Lightning.AdaptorRegistry.all()
      |> Enum.map(&Map.get(&1, :name))
      |> Enum.sort()

    {module_name, version, versions} =
      if adaptor do
        {module_name, version} =
          Lightning.AdaptorRegistry.resolve_package_name(adaptor)

        versions =
          Lightning.AdaptorRegistry.versions_for(module_name)
          |> List.wrap()
          |> Enum.map(&Map.get(&1, :version))
          |> Enum.sort_by(&Version.parse(&1), :desc)
          |> Enum.map(fn version ->
            [key: version, value: "#{module_name}@#{version}"]
          end)

        {module_name, version,
         [[key: "latest", value: "#{module_name}@latest"] | versions]}
      else
        {nil, nil, []}
      end

    {module_name, version, adaptor_names, versions}
  end

  @impl true
  def handle_event(event, params, socket) do
    case event do
      "validate" ->
        {:noreply, validate(params, socket)}

      "save" ->
        {:noreply, save(params, socket)}
    end
  end

  @doc """
  Coerce any changes to the "Adaptor" dropdown into a new selection on the
  Version dropdown.
  """
  @spec coerce_params_for_adaptor_list(%{String.t() => String.t()}) ::
          %{}
  def coerce_params_for_adaptor_list(job_params) do
    {package, _version} =
      AdaptorRegistry.resolve_package_name(job_params["adaptor"])

    {package_group, _} =
      AdaptorRegistry.resolve_package_name(job_params["adaptor_name"])

    cond do
      is_nil(package_group) ->
        Map.merge(job_params, %{"adaptor" => ""})

      package_group !== package ->
        Map.merge(job_params, %{"adaptor" => "#{package_group}@latest"})

      true ->
        job_params
    end
  end

  def requires_upstream_job?(changeset) do
    get_field(changeset, :trigger_type) in [:on_job_failure, :on_job_success]
  end

  def requires_cron_job?(changeset) do
    get_field(changeset, :trigger_type) == :cron
  end

  @impl true
  def save(%{"job_form" => job_params}, socket) do
    %{action: action, job_form: job_form} = socket.assigns

    case action do
      :edit ->
        job_form
        |> JobForm.changeset(job_params)
        |> JobForm.to_multi(job_params)
        |> Lightning.Repo.transaction()
        |> case do
          {:ok, _job} ->
            LightningWeb.Endpoint.broadcast!(
              "project_space:#{socket.assigns.project.id}",
              "update",
              %{}
            )

            socket
            |> put_flash(:info, "Job updated successfully")
            |> redirect_or_patch(to: socket.assigns.return_to)

          {:error, %Ecto.Changeset{} = changeset} ->
            assign(socket, :changeset, changeset)
        end

      :new ->
        job_form
        |> JobForm.changeset(job_params)
        |> JobForm.to_multi(job_params)
        |> Lightning.Repo.transaction()
        |> case do
          {:ok, _job} ->
            LightningWeb.Endpoint.broadcast!(
              "project_space:#{socket.assigns.project.id}",
              "update",
              %{}
            )

            socket
            |> put_flash(:info, "Job created successfully")
            |> redirect_or_patch(to: socket.assigns.return_to)

          {:error, %Ecto.Changeset{} = changeset} ->
            assign(socket, changeset: changeset)
        end
    end
  end

  defp redirect_or_patch(socket, to: to) do
    case socket.view do
      LightningWeb.WorkflowLive ->
        socket |> push_patch(to: to)

      _ ->
        socket |> push_redirect(to: to)
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
            <%= label f, :trigger_type, class: "block" do %>
              <span class="block text-sm font-medium text-secondary-700">
                Trigger
              </span>
              <%= error_tag(f, :trigger_type, class: "block w-full rounded-md") %>
              <Form.select_field
                form={f}
                name={:trigger_type}
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

            <%= if f.data.id && @id do %>
              <a
                id="copyWebhookUrl"
                href={Routes.webhooks_url(@socket, :create, [@id])}
                onclick="(function(e) {  navigator.clipboard.writeText(e.target.href); e.preventDefault(); })(event)"
                target="_blank"
              >
                Copy webhook url
              </a>
            <% end %>

            <%= if requires_upstream_job?(f.source) do %>
              <%= label f, :trigger_upstream_job_id, class: "block" do %>
                <span class="block text-sm font-medium text-secondary-700">
                  Upstream Job
                </span>
                <%= error_tag(f, :trigger_upstream_job_id,
                  class: "block w-full rounded-md"
                ) %>
                <Form.select_field
                  form={f}
                  name={:trigger_upstream_job_id}
                  prompt=""
                  id="upstreamJob"
                  values={Enum.map(@upstream_jobs, &{&1.name, &1.id})}
                />
              <% end %>
            <% end %>
            <%= if requires_cron_job?(f.source) do %>
              <Form.text_field form={f} id={:trigger_cron_expression} />
            <% end %>
          </div>

          <div class="md:col-span-1">
            <Components.Jobs.credential_select form={f} credentials={@credentials} />
            <button
              id="new-credential-launcher"
              type="button"
              phx-click={
                Phoenix.LiveView.JS.push("new-credential", value: @job_params)
              }
            >
              New credential
            </button>
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
              id="editor-component"
              class="rounded-md border border-secondary-300 shadow-sm h-96 bg-vs-dark"
              data-adaptor={Phoenix.HTML.Form.input_value(f, :adaptor)}
              data-hidden-input={Phoenix.HTML.Form.input_id(f, :body)}
              data-job-id={@id}
            />
            <Form.hidden_input form={f} id={:body} />
          </div>
          <div class="md:col-span-2 w-full">
            <span>
              <%= live_patch("Cancel",
                class:
                  "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500",
                to: Routes.project_workflow_path(@socket, :show, @project.id)
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
