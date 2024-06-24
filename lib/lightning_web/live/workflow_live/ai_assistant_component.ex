defmodule LightningWeb.WorkflowLive.AiAssistantComponent do
  alias Phoenix.LiveView.AsyncResult
  use LightningWeb, :live_component

  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [
       %{id: 2, role: :assistant, content: "Hello, how can I help you?"},
       %{id: 1, role: :user, content: "Hello, I'm here to be helped."}
     ])
     |> assign(%{
       pending_message: AsyncResult.ok(nil),
       form: to_form(%{content: nil})
     })}
  end

  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 grid-rows-2 gap-4 h-full">
      <div class="row-span-full">
        <div class="flex flex-col-reverse gap-4">
          <%= for message <- @messages do %>
            <div
              :if={message.role == :user}
              class="ml-auto bg-blue-500 text-white p-2 rounded-lg max-w-fit text-right"
            >
              <%= message.content %>
            </div>
            <div
              :if={message.role == :assistant}
              class="mr-auto bg-gray-200 text-gray-800 p-2 rounded-lg max-w-fit"
            >
              <%= message.content %>
            </div>
          <% end %>
        </div>
      </div>
      <.form
        for={@form}
        phx-submit="send_message"
        class="row-span-1"
        phx-target={@myself}
      >
        <.chat_input form={@form} disabled={not is_nil(@pending_message.loading)} />
      </.form>
    </div>
    """
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    response_id = Ecto.UUID.generate()

    socket =
      socket
      |> update(:messages, fn messages ->
        [
          %{role: :assistant, content: "...", id: response_id},
          %{role: :user, content: content} | messages
        ]
      end)
      |> assign(:pending_message, AsyncResult.loading())
      |> start_async(
        :process_message,
        fn ->
          Process.sleep(1000)

          %{
            id: response_id,
            role: :assistant,
            content: "Got it!"
          }
        end
      )

    {:noreply, socket}
  end

  def handle_async(:process_message, {:ok, message}, socket) do
    {:noreply,
     socket
     |> update(:messages, fn messages ->
       messages
       |> Enum.find_index(&(&1.id == message.id))
       |> then(fn index -> List.replace_at(messages, index, message) end)
     end)
     |> assign(:pending_message, AsyncResult.ok(nil))}
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
    <div class="min-w-0 flex-1">
      <div class="overflow-hidden rounded-lg shadow-sm ring-1 ring-inset ring-gray-300 focus-within:ring-2 focus-within:ring-indigo-600">
        <label for={@form[:content].name} class="sr-only">
          Describe your request
        </label>
        <textarea
          id="content"
          name={@form[:content].name}
          rows="3"
          class="block w-full resize-none border-0 bg-transparent py-1.5 text-gray-900 placeholder:text-gray-400 focus:ring-0 sm:text-sm sm:leading-6"
          placeholder="..."
          disabled={@disabled}
        ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:content].value) %></textarea>
        <.error :for={msg <- @errors}><%= msg %></.error>
      </div>

      <div class="relative">
        <div class="absolute inset-x-0 bottom-0 flex justify-between py-2 pl-3 pr-2">
          <div class="flex items-center space-x-5"></div>
          <div class="flex-shrink-0">
            <.button type="submit" disabled={@disabled}>
              Send
            </.button>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
