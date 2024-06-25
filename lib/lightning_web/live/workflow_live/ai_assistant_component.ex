defmodule LightningWeb.WorkflowLive.AiAssistantComponent do
  use LightningWeb, :live_component
  alias Lightning.AiAssistant
  alias Phoenix.LiveView.AsyncResult

  def mount(socket) do
    {:ok,
     socket
     |> assign(%{
       pending_message: AsyncResult.ok(nil),
       form: to_form(%{"content" => nil})
     })
     |> assign_async(:endpoint_available?, fn ->
       {:ok, %{endpoint_available?: AiAssistant.endpoint_available?()}}
     end)}
  end

  def update(%{selected_job: job} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(session: AiAssistant.new_session(job))}
  end

  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 grid-rows-2 gap-4 h-full flow-root">
      <.async_result :let={endpoint_available?} assign={@endpoint_available?}>
        <:loading>
          <div class="row-span-full flex items-center justify-center">
            <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
              <.icon name="hero-sparkles" class="animate-pulse" />
            </div>
          </div>
        </:loading>
        <div class="row-span-full flex flex-col gap-4 p-2 overflow-y-auto">
          <%= for message <- @session.history do %>
            <div
              :if={message.role == "user"}
              class="ml-auto bg-blue-500 text-white p-2 rounded-lg text-right break-words"
            >
              <%= message.content %>
            </div>
            <div
              :if={message.role == "assistant"}
              class="mr-auto p-2 rounded-lg break-words text-wrap flex flex-row gap-x-2 makeup-html"
            >
              <div class="">
                <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
                  <.icon name="hero-cpu-chip" class="" />
                </div>
              </div>

              <div>
                <%= message.content |> Earmark.as_html!() |> raw() %>
              </div>
            </div>
          <% end %>
          <.async_result assign={@pending_message}>
            <:loading>
              <div class="mr-auto p-2 rounded-lg break-words text-wrap flex flex-row gap-x-2 animate-pulse">
                <div class="">
                  <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
                    <.icon name="hero-sparkles" class="" />
                  </div>
                </div>
                <div class="h-2 bg-slate-700 rounded"></div>
              </div>
            </:loading>
            <:failed>
              <div class="mr-auto p-2 rounded-lg break-words text-wrap flex flex-row gap-x-2">
                <div class="">
                  <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
                    <.icon name="hero-sparkles" class="" />
                  </div>
                </div>
                <div class="flex gap-2">
                  <.icon name="exclamation-triangle" class="text-red" />
                  <span>An error occured! Please try again later.</span>
                </div>
              </div>
            </:failed>
          </.async_result>
        </div>
        <.form
          for={@form}
          phx-submit="send_message"
          class="row-span-1 p-2 pt-0"
          phx-target={@myself}
        >
          <.chat_input
            form={@form}
            disabled={!endpoint_available? or !is_nil(@pending_message.loading)}
          />
        </.form>
      </.async_result>
    </div>
    """
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    {:noreply,
     socket
     |> assign(:pending_message, AsyncResult.loading())
     |> assign(
       :session,
       AiAssistant.push_history(socket.assigns.session, %{
         "role" => "user",
         "content" => content
       })
     )
     |> start_async(
       :process_message,
       fn ->
         AiAssistant.query(socket.assigns.session, content)
       end
     )}
  end

  def handle_async(:process_message, {:ok, {:ok, session}}, socket) do
    {:noreply,
     socket
     |> assign(:session, session)
     |> assign(:pending_message, AsyncResult.ok(nil))}
  end

  def handle_async(:process_message, {:ok, :error}, socket) do
    {:noreply,
     socket
     |> assign(:pending_message, AsyncResult.failed(nil, :error))}
  end

  attr :disabled, :boolean
  attr :form, :map, required: true

  defp chat_input(assigns) do
    assigns =
      assigns
      |> assign(
        :errors,
        Enum.map(
          assigns.form[:content].errors,
          &LightningWeb.CoreComponents.translate_error(&1)
        )
      )

    ~H"""
    <div class="w-full max-h-72 flex flex-row rounded-lg shadow-sm ring-1 ring-inset ring-gray-300 focus-within:ring-2 focus-within:ring-indigo-600">
      <label for={@form[:content].name} class="sr-only">
        Describe your request
      </label>
      <textarea
        id="content"
        name={@form[:content].name}
        class="block grow resize-none border-0 bg-transparent py-1.5 text-gray-900 placeholder:text-gray-400 focus:ring-0 text-sm"
        placeholder="..."
        disabled={@disabled}
      ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:content].value) %></textarea>
      <.error :for={msg <- @errors}><%= msg %></.error>
      <div class="py-2 pl-3 pr-2">
        <div class="flex items-center space-x-5"></div>
        <div class="flex-shrink-0">
          <.button type="submit" disabled={@disabled}>
            Send
          </.button>
        </div>
      </div>
    </div>
    """
  end
end
