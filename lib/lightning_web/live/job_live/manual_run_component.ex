defmodule LightningWeb.JobLive.ManualRunComponent do
  use LightningWeb, :live_component

  alias LightningWeb.Components.Form
  alias Lightning.Repo

  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(job_id: assigns.job_id, current_user: assigns.current_user)
     |> update_form(%{})}
  end

  def handle_event("confirm", _params, socket) do
    socket.assigns.changeset
    |> Ecto.Changeset.put_change(:user, socket.assigns.current_user)
    |> create_manual_workorder()
    |> case do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Run enqueued.")}

      {:error, changeset} ->
        {:noreply,
         socket
         |> assign(
           changeset: changeset,
           form: Phoenix.HTML.FormData.to_form(changeset, as: "manual_run")
         )}
    end
  end

  def handle_event("changed", params, socket) do
    {:noreply, socket |> update_form(params)}
  end

  defp update_form(socket, params) do
    changeset =
      changeset(params["manual_run"] || %{})
      |> Ecto.Changeset.put_change(:job_id, socket.assigns.job_id)
      |> Ecto.Changeset.put_change(:user, socket.assigns.current_user)
      |> Map.put(:action, :validate)

    socket
    |> assign(
      changeset: changeset,
      form: Phoenix.HTML.FormData.to_form(changeset, as: "manual_run")
    )
  end

  defp changeset(attrs) do
    data = %{dataclip_id: nil, job_id: nil, user: nil}
    types = %{dataclip_id: Ecto.UUID, job_id: Ecto.UUID, user: :map}

    Ecto.Changeset.cast({data, types}, attrs, [:dataclip_id])
    |> Ecto.Changeset.validate_required([:dataclip_id])
  end

  defp create_manual_workorder(changeset) do
    with {:ok, dataclip} <- get_dataclip(changeset),
         {:ok, job} <- get_job(changeset),
         user <- changeset |> Ecto.Changeset.get_field(:user) do
      {:ok, %{attempt_run: attempt_run}} =
        Lightning.WorkOrderService.multi_for_manual(job, dataclip, user)
        |> Repo.transaction()

      Lightning.Pipeline.new(%{attempt_run_id: attempt_run.id})
      |> Oban.insert()
    end
  end

  defp get_dataclip(changeset) do
    changeset
    |> Ecto.Changeset.get_field(:dataclip_id)
    |> Lightning.Invocation.get_dataclip()
    |> case do
      nil ->
        {:error,
         changeset |> Ecto.Changeset.add_error(:dataclip_id, "doesn't exist")}

      d ->
        {:ok, d}
    end
  end

  defp get_job(changeset) do
    changeset
    |> Ecto.Changeset.get_field(:job_id)
    |> Lightning.Jobs.get_job()
    |> case do
      nil ->
        {:error, changeset |> Ecto.Changeset.add_error(:job_id, "doesn't exist")}

      j ->
        {:ok, j}
    end
  end

  def render(assigns) do
    ~H"""
    <div>
      <Form.text_field
        form={@form}
        id={:dataclip_id}
        phx_change="changed"
        phx_target={@myself}
      />
      <Common.button
        text="Run"
        disabled={!@changeset.valid?}
        phx-click="confirm"
        phx_target={@myself}
      />
      <.live_info_block myself={@myself} flash={@flash} />
    </div>
    """
  end
end
