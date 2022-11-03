defmodule LightningWeb.JobLive.JobSetupComponent do
  @moduledoc """
  JobSetupComponent
  """

  use LightningWeb, :live_component

  import Ecto.Changeset, only: [get_field: 2]

  alias Lightning.{Jobs, Projects}
  alias LightningWeb.Components.Form
  alias LightningWeb.JobLive.JobBuilder
  alias Jobs.JobForm

  defp id(job) do
    "job-form-#{job.id}"
  end

  def send_body(job, body) do
    send_update(__MODULE__, id: id(job), body: body)
  end

  @impl true
  def update(%{cron_expression: cron_expression}, socket) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.apply_changes()
      |> JobForm.changeset(%{
        "trigger_cron_expression" => cron_expression
      })
      |> Map.put(:action, :validate)

    {:ok, assign(socket, changeset: changeset)}
  end

  def update(%{adaptor: adaptor}, socket) do
    changeset =
      socket.assigns.changeset
      |> Ecto.Changeset.apply_changes()

    JobForm.changeset(%{
      "adaptor" => adaptor
    })
    |> Map.put(:action, :validate)

    JobBuilder.send_adaptor(socket.assigns.changeset.data.id, adaptor)

    {:ok, assign(socket, changeset: changeset)}
  end

  def update(%{body: body}, socket) do
    changeset =
      JobForm.changeset(socket.assigns.changeset, %{
        "body" => body
      })
      |> Map.put(:action, :validate)

    {:ok, assign(socket, changeset: changeset)}
  end

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

    credentials = Projects.list_project_credentials(project)

    upstream_jobs = Jobs.get_upstream_jobs_for(job_form)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       credentials: credentials,
       upstream_jobs: upstream_jobs,
       job_form: job_form,
       changeset: changeset,
       job_params: %{},
       id: id(job_form)
     )}
  end

  def validate(%{"job_form" => job_params}, socket) do
    changeset =
      JobForm.changeset(socket.assigns.changeset, job_params)
      |> Map.put(:action, :validate)

    assign(socket, changeset: changeset, job_params: job_params)
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

  def webhook?(changeset) do
    get_field(changeset, :trigger_type) in [:webhook]
  end

  def requires_upstream_job?(changeset) do
    get_field(changeset, :trigger_type) in [:on_job_failure, :on_job_success]
  end

  def requires_cron_job?(changeset) do
    get_field(changeset, :trigger_type) == :cron
  end

  defp insert_cron_expression(changeset, job_params) do
    if Map.has_key?(changeset.changes, :trigger_cron_expression) do
      Map.put_new(
        job_params,
        "trigger_cron_expression",
        changeset.changes.trigger_cron_expression
      )
    else
      job_params
    end
  end

  def save(%{"job_form" => job_params}, socket) do
    %{action: action, changeset: changeset} = socket.assigns

    job_params = insert_cron_expression(changeset, job_params)

    case action do
      :edit ->
        changeset
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
        changeset
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
end
