defmodule LightningWeb.WorkflowLive.Collaborate do
  @moduledoc """
  LiveView for collaborative workflow editing using Yjs.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Workflows

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    workflow = Workflows.get_workflow!(workflow_id)

    # Initialize Y.Doc with this LiveView process as the worker
    ydoc = Yex.Doc.new(self())

    # Create a text field for collaborative editing
    text_field = Yex.Doc.get_text(ydoc, "workflow_content")

    # Create a map for storing counter
    counter_map = Yex.Doc.get_map(ydoc, "counter_data")

    # Set initial content
    :ok =
      Yex.Doc.transaction(ydoc, fn ->
        Yex.Text.insert(text_field, 0, "Hello World from Y.Doc!")
        Yex.Map.set(counter_map, "value", 0)
      end)

    # Monitor updates to the ydoc
    {:ok, _sub_ref} = Yex.Doc.monitor_update(ydoc)

    # Get initial text content and counter value
    initial_content = Yex.Text.to_string(text_field)
    initial_counter = Yex.Map.fetch!(counter_map, "value") || 0

    IO.inspect({initial_content, initial_counter}, label: "mount")
    # Start the counter timer
    Process.send_after(self(), :increment_counter, 1000)

    {:ok,
     socket
     |> assign(
       active_menu_item: :overview,
       page_title: "Collaborate on #{workflow.name}",
       workflow: workflow,
       ydoc: ydoc,
       text_field: text_field,
       counter_map: counter_map,
       content: initial_content,
       counter: initial_counter
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # Required by Y.Doc when using this process as worker
  @impl true
  def handle_call({Yex.Doc, :run, fun}, _from, socket) do
    result = fun.()
    {:reply, result, socket}
  end

  # Handle Y.Doc update messages
  @impl true
  def handle_info({:update_v1, _update_binary, _origin, _metadata}, socket) do
    # Update the content when ydoc changes
    updated_content = Yex.Text.to_string(socket.assigns.text_field)
    updated_counter = Yex.Map.fetch!(socket.assigns.counter_map, "value") || 0

    IO.inspect({updated_content, updated_counter}, label: "handle_info")

    {:noreply,
     assign(socket, content: updated_content, counter: updated_counter)}
  end

  # Handle counter increment timer
  @impl true
  def handle_info(:increment_counter, socket) do
    counter_map = socket.assigns.counter_map
    ydoc = socket.assigns.ydoc
    current_counter = Yex.Map.fetch!(counter_map, "value") || 0
    new_counter = current_counter + 1

    # Update counter in Y.Doc
    _result =
      Yex.Doc.transaction(ydoc, fn ->
        Yex.Map.set(counter_map, "value", new_counter)
      end)

    # Schedule next increment
    Process.send_after(self(), :increment_counter, 1000)

    {:noreply, socket}
  end

  # Handle content updates from the UI
  @impl true
  def handle_event("update_content", %{"value" => new_content}, socket) do
    text_field = socket.assigns.text_field
    ydoc = socket.assigns.ydoc

    # Clear and set new content in a transaction
    _result =
      Yex.Doc.transaction(ydoc, fn ->
        current_length = Yex.Text.length(text_field)

        if current_length > 0 do
          Yex.Text.delete(text_field, 0, current_length)
        end

        Yex.Text.insert(text_field, 0, new_content)
      end)

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex-1 p-4">
        <h2 class="text-2xl font-bold mb-4">
          Y.Doc Collaborative Editor - {@workflow.name}
        </h2>

        <div class="mb-6 p-4 bg-blue-50 rounded-lg">
          <h3 class="text-lg font-semibold text-blue-800 mb-2">
            Y.Doc Counter
          </h3>
          <div class="text-3xl font-bold text-blue-600">
            {@counter}
          </div>
          <p class="text-sm text-blue-600 mt-1">
            Auto-incrementing every second (stored in Y.Doc Map)
          </p>
        </div>

        <div class="space-y-4">
          <div>
            <label for="content" class="block text-sm font-medium text-gray-700">
              Content (Y.Doc Text)
            </label>
            <textarea
              id="content"
              name="content"
              rows="10"
              class="mt-1 block w-full rounded-md border-gray-300 shadow-sm
                     focus:border-indigo-500 focus:ring-indigo-500"
              phx-keyup="update_content"
              phx-debounce="300"
            ><%= @content %></textarea>
          </div>

          <div class="text-sm text-gray-500">
            <p>This content is stored in a Y.Doc CRDT structure.</p>
            <p>Current content length: {String.length(@content)} characters</p>
            <p>Counter value: {@counter} (auto-increments via Y.Doc Map)</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
