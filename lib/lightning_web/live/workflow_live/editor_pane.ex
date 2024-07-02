defmodule LightningWeb.WorkflowLive.EditorPane do
  use LightningWeb, :live_component

  alias Lightning.Credentials
  alias LightningWeb.JobLive.JobBuilderComponents

  attr :id, :string, required: true
  attr :disabled, :boolean, default: false
  attr :disabled_message, :string, required: true
  attr :class, :string, default: ""
  attr :on_change, :any, required: true
  attr :adaptor, :string, required: true
  attr :source, :string, required: true
  attr :job_id, :string, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class={@class}>
      <JobBuilderComponents.job_editor_component
        adaptor={@adaptor}
        source={@source}
        id={"job-editor-#{@job_id}"}
        job_id={@job_id}
        disabled={@disabled}
        disabled_message={@disabled_message}
        phx-target={@myself}
      />
    </div>
    """
  end

  @impl true
  def update(%{event: :metadata_ready, metadata: metadata}, socket) do
    {:ok, socket |> push_event("metadata_ready", metadata)}
  end

  def update(%{form: form} = assigns, socket) do
    socket =
      socket
      |> assign(
        adaptor:
          form[:adaptor].value
          |> Lightning.AdaptorRegistry.resolve_adaptor(),
        source: form.source.data.body,
        job_id: form[:id].value
      )

    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def handle_event("request_metadata", _params, socket) do
    pid = self()

    %{adaptor: adaptor, id: id, form: form} = socket.assigns

    credential = fetch_credential(form[:project_credential_id].value)

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
        id: id,
        metadata: metadata,
        event: :metadata_ready
      )
    end)

    {:noreply, socket}
  end

  def handle_event("job_body_changed", %{"source" => source}, socket) do
    params =
      {socket.assigns.form[:body].name, source}
      |> LightningWeb.Utils.decode_one()

    send(self(), {"form_changed", params})

    {:noreply, socket}
  end

  defp fetch_credential(id) do
    case Ecto.UUID.cast(id) do
      {:ok, _uuid} -> Credentials.get_credential_by_project_credential(id)
      :error -> nil
    end
  end
end
