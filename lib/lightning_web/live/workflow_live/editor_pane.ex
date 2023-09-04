defmodule LightningWeb.WorkflowLive.EditorPane do
  use LightningWeb, :live_component
  alias LightningWeb.JobLive.JobBuilderComponents
  import LightningWeb.WorkflowLive.Components

  attr :id, :string, required: true
  attr :disabled, :boolean, default: false
  attr :class, :string, default: ""
  attr :on_change, :any, required: true
  attr :adaptor, :string, required: true
  attr :source, :string, required: true
  attr :job_id, :string, required: true

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-full" id={@id}>
    <div class="flex justify-between items-center header_2_class">
    <div class="text-xl text-center font-semibold text-secondary-700 panel-2-header-title">
        Editor
      </div>
      <div class="panel_2_icons">
        <div phx-click={hide_panel_2()}>
          <Heroicons.minus_small class="w-10 h-10 p-2 hover:bg-gray-200 text-gray-600 rounded-lg header-icon-before-2"/>
        </div>
        <div phx-click={show_panel_2()}>
          <Heroicons.plus class="hidden w-10 h-10 p-2 hover:bg-gray-200 text-gray-600 rounded-lg header-icon-after-2"/>
        </div>
        </div>
    </div>
    <div class={@class} id="panel-2-content">
        <JobBuilderComponents.job_editor_component
          adaptor={@adaptor}
          source={@source}
          id={"job-editor-#{@job_id}"}
          disabled={@disabled}
          phx-target={@myself}
        />
    </div>

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
          form
          |> input_value(:adaptor)
          |> Lightning.AdaptorRegistry.resolve_adaptor(),
        source: form |> input_value(:body),
        credential: form |> input_value(:credential),
        job_id: form |> input_value(:id)
      )

    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def handle_event("request_metadata", _params, socket) do
    pid = self()

    %{adaptor: adaptor, credential: credential, id: id} = socket.assigns

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
      {Phoenix.HTML.Form.input_name(socket.assigns.form, :body), source}
      |> Plug.Conn.Query.decode_pair(%{})

    send(self(), {"form_changed", params})

    {:noreply, socket}
  end
end
