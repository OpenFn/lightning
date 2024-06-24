defmodule LightningWeb.WorkflowLive.AiAssistantComponent do
  use LightningWeb, :live_component
  alias Phoenix.LiveView.AsyncResult

  def mount(socket) do
    {:ok,
     socket
     |> assign(:messages, [
       %{
         id: 4,
         role: :assistant,
         content:
           "Based on the provided guide and the API documentation for the OpenFn @openfn/language-common@1.14.0 adaptor, you can create jobs using the functions provided by the API to interact with different data sources and perform various operations.\n\nTo create a job using the HTTP adaptor, you can use functions like `get`, `post`, `put`, `patch`, `head`, and `options` to make HTTP requests. Here's an example job code using the HTTP adaptor:\n\n```javascript\nconst { get, post, each, dataValue } = require('@openfn/language-common');\n\nexecute(\n  get('/patients'),\n  each('$.data.patients[*]', (item, index) => {\n    item.id = `item-${index}`;\n  }),\n  post('/patients', dataValue('patients'))\n);\n```\n\nIn this example, the job first fetches patient data using a GET request, then iterates over each patient to modify their ID, and finally posts the modified patient data back.\n\nYou can similarly create jobs using the Salesforce adaptor or the ODK adaptor by utilizing functions like `upsert`, `create`, `fields`, `field`, etc., as shown in the provided examples.\n\nFeel free to ask if you have any specific questions or need help with"
       },
       %{id: 3, role: :user, content: "what?"},
       %{id: 2, role: :assistant, content: "Hello, how can I help you?"},
       %{id: 1, role: :user, content: "Hello, I'm here to be helped."}
     ])
     |> assign(%{
       pending_message: AsyncResult.ok(nil),
       form: to_form(%{"content" => nil})
     })}
  end

  def render(assigns) do
    ~H"""
    <div class="grid grid-cols-1 grid-rows-2 gap-4 h-full">
      <div class="row-span-full flex flex-col-reverse gap-4 overflow-y-auto">
        <%= for message <- @messages do %>
          <div
            :if={message.role == :user}
            class="ml-auto bg-blue-500 text-white p-2 rounded-lg text-right break-words"
          >
            <%= message.content %>
          </div>
          <div
            :if={message.role == :assistant}
            class="mr-auto bg-gray-200 text-gray-800 p-2 rounded-lg break-words text-wrap max-w-full makeup-html"
          >
            <%= message.content |> Earmark.as_html!() |> raw() %>
          </div>
        <% end %>
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
