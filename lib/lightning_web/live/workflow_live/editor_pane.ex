defmodule LightningWeb.WorkflowLive.EditorPane do
  use LightningWeb, :live_component
  import LightningWeb.JobLive.JobBuilderComponents

  attr :job, :map, required: true
  attr :disabled, :boolean, default: false
  attr :class, :string, default: ""
  attr :on_change, :any, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class={@class}>
      <.job_editor_component
        adaptor={@job.adaptor}
        source={@job.body}
        id={"job-editor-#{@job.id}"}
        disabled={@disabled}
        phx-target={@myself}
      />
    </div>
    """
  end

  @impl true
  def update(%{job: job} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       job: job,
       disabled: assigns |> Map.get(:disabled, false),
       class: assigns |> Map.get(:class, ""),
       form: assigns |> Map.get(:form)
     )}
  end

  def update(%{event: :metadata_ready, metadata: metadata}, socket) do
    {:ok, socket |> push_event("metadata_ready", metadata)}
  end

  @impl true
  def handle_event("request_metadata", _params, socket) do
    pid = self()

    adaptor = socket.assigns.job.adaptor

    credential = socket.assigns.job.credential

    Task.start(fn ->
      metadata =
        Lightning.MetadataService.fetch(adaptor, credential)
        |> case do
          {:error, %{type: error_type}} ->
            %{"error" => error_type}

          {:ok, metadata} ->
            metadata
        end

      send_update(pid, __MODULE__,
        id: socket.assigns.job.id,
        metadata: metadata,
        event: :metadata_ready
      )
    end)

    {:noreply, socket}
  end

  def handle_event("job_body_changed", %{"source" => source}, socket) do
    form =
      Phoenix.HTML.Form.inputs_for(socket.assigns.form, :jobs)
      |> Enum.find(
        &(Ecto.Changeset.get_field(&1.source, :id) == socket.assigns.job.id)
      )

    params =
      {Phoenix.HTML.Form.input_name(form, :body), source}
      |> Plug.Conn.Query.decode_pair(%{})

    # send(self(), {"job_body_changed", %{id: id, source: source}})
    send(self(), {"form_changed", params})

    {:noreply, socket}
  end
end
