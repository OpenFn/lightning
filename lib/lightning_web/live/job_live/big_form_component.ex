defmodule LightningWeb.JobLive.BigFormComponent do
  @moduledoc """
  Form Component for working with a single Job

  A Job's `adaptor` field is a combination of the module name and the version.
  It's formatted as an NPM style string.

  The form allows the user to select a module by name and then it's version,
  while the version dropdown itself references `adaptor` directly.

  Meaning the `adaptor_name` dropdown and assigns value is not persisted.
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
end
