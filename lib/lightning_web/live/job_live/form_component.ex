defmodule LightningWeb.JobLive.FormComponent do
  use LightningWeb, :live_component

  alias Lightning.Jobs

  @impl true
  def update(%{job: job} = assigns, socket) do
    changeset = Jobs.change_job(job)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"job" => job_params}, socket) do
    changeset =
      socket.assigns.job
      |> Jobs.change_job(job_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"job" => job_params}, socket) do
    save_job(socket, socket.assigns.action, job_params)
  end

  defp save_job(socket, :edit, job_params) do
    case Jobs.update_job(socket.assigns.job, job_params) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Job updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_job(socket, :new, job_params) do
    case Jobs.create_job(job_params) do
      {:ok, _job} ->
        {:noreply,
         socket
         |> put_flash(:info, "Job created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
