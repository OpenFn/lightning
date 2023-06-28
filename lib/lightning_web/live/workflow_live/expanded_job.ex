defmodule LightningWeb.WorkflowLive.ExpandedJobModal do
  use LightningWeb, :live_component
  import LightningWeb.JobLive.JobBuilderComponents

  @impl true
  def update(%{job: _} = assigns, socket) do
    {:ok, socket |> assign(assigns)}
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
        id: socket.assigns.job_id,
        metadata: metadata,
        event: :metadata_ready
      )
    end)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="h-screen overscroll-none">
      <div class="grid grid-cols-3 divide-x h-1/6">
        <span><%= @job.adaptor %></span>
        <span>
          <%= if @job.credential != nil do %>
            <%= @job.credential.name %>
          <% else %>
            <%= "No Credentials" %>
          <% end %>
        </span>
        <span><%= @job.name %></span>
      </div>
      <div class="h-5/6">
        <div class="h-5/6 grid grid-cols-3 divide-x">
          <div>Input</div>
          <div>
            <.job_editor_component
              adaptor={@job.adaptor}
              source={@job.body}
              id={"job-editor-#{@job_id}"}
              disabled={!@can_edit_job}
              phx-target={@myself}
            />
          </div>
          <div>Output</div>
        </div>
        <div class="h-1/6">
          <span> Reruns  Buttons </span>
        </div>
      </div>
    </div>
    """
  end
end
