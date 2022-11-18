defmodule LightningWeb.JobLive.ManualRunComponent do
  use LightningWeb, :live_component

  alias LightningWeb.Components.Form
  alias Lightning.Repo

  attr :job_id, :string, required: true
  attr :current_user, Lightning.Accounts.User, required: true

  def render(assigns) do
    ~H"""
    <div id={@id} class="h-full">
      <.form
        :let={f}
        for={@changeset}
        as={:manual_run}
        phx-target={@myself}
        class="h-full flex flex-col"
      >
        <%= error_tag(f, :dataclip_id) %>
        <Form.select_field
          form={f}
          name={:dataclip_id}
          id={:dataclip_id}
          values={@dataclips_options}
          selected={@selected}
          phx-change="changed"
          phx-target={@myself}
          prompt=""
        />
        <div class="flex-1 bg-gray-100 p-3 font-mono"><%= @selected_body %></div>
        <Common.button
          text="Run"
          disabled={!@changeset.valid?}
          phx-click="confirm"
          phx-target={@myself}
        />
        <.live_info_block myself={@myself} flash={@flash} />
      </.form>
    </div>
    """
  end

  @impl true
  def update(%{job_id: job_id, current_user: current_user, id: id}, socket) do
    dataclips =
      Lightning.Invocation.list_dataclips_for_job(%Lightning.Jobs.Job{id: job_id})

    dataclips_options = dataclips |> Enum.map(&{&1.id, &1.id})
    most_recent_dataclip = List.first(dataclips)

    init_form =
      unless most_recent_dataclip == nil do
        %{"manual_run" => %{dataclip_id: most_recent_dataclip.id}}
      else
        %{}
      end

    {:ok,
     socket
     |> assign(
       job_id: job_id,
       current_user: current_user,
       id: id,
       dataclips: dataclips,
       dataclips_options: dataclips_options,
       selected:
         unless most_recent_dataclip == nil do
           most_recent_dataclip.id
         else
           nil
         end
     )
     |> update_form(init_form)}
  end

  @impl true
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
    |> update_selection(changeset)
  end

  defp update_selection(socket, changeset) do
    id = Ecto.Changeset.get_field(changeset, :dataclip_id)
    dataclips = socket.assigns.dataclips

    selected_dataclip = Enum.find(dataclips, fn d -> d.id == id end)

    socket
    |> assign(
      selected_body:
        unless is_nil(selected_dataclip) do
          selected_dataclip.body
        else
          ""
        end
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
end
