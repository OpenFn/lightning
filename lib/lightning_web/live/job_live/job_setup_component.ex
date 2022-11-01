defmodule LightningWeb.JobLive.JobSetupComponent do
  @moduledoc """
  JobSetupComponent
  """

  use LightningWeb, :live_component

  import Ecto.Changeset, only: [get_field: 2]

  alias Lightning.{Jobs, Projects}
  alias LightningWeb.Components.Form
  alias Jobs.JobForm

  @impl true
  def update(
        %{
          job_form: job_form,
          project: project,
          initial_job_params: initial_job_params
        } = assigns,
        socket
      ) do
    changeset =
      JobForm.changeset(
        job_form,
        initial_job_params
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
     |> assign(:credentials, credentials)
     |> assign(:upstream_jobs, upstream_jobs)
     |> assign(:job_form, job_form)
     |> assign(:job_body, job_form.body)
     |> assign(:changeset, changeset)
     |> assign(:job_params, %{})}
  end

  def validate(%{"job_form" => job_params}, socket) do
    changeset =
      JobForm.changeset(socket.assigns.changeset, job_params)
      |> Map.put(:action, :validate)

    assign(socket, changeset: changeset, job_params: job_params)
  end

  def handle_event("job_body_changed", %{"source" => source}, socket) do
    {:noreply, socket |> assign(job_body: source)}
  end

  @impl true
  def handle_event(
        "adaptor_name_change",
        %{"adaptor_component" => %{"adaptor_name" => adaptor_name}},
        socket
      ) do
    changeset =
      JobForm.changeset(socket.assigns.changeset, %{
        "adaptor" => "#{adaptor_name}@latest"
      })
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
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

  def requires_upstream_job?(changeset) do
    get_field(changeset, :trigger_type) in [:on_job_failure, :on_job_success]
  end

  def requires_cron_job?(changeset) do
    get_field(changeset, :trigger_type) == :cron
  end

  def save(%{"job_form" => job_params}, socket) do
    %{action: action, job_form: job_form, job_body: job_body} = socket.assigns

    case action do
      :edit ->
        job_form
        |> JobForm.changeset(job_params)
        |> JobForm.put_body(job_body)
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
        |> JobForm.put_body(job_body)
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
