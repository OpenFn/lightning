defmodule LightningWeb.WorkflowLive.AiAssistantComponent do
  use LightningWeb, :live_component
  alias Lightning.AiAssistant
  alias Phoenix.LiveView.AsyncResult

  def mount(socket) do
    {:ok,
     socket
     |> assign(%{
       pending_message: AsyncResult.ok(nil),
       process_message_on_show: false,
       all_sessions: AsyncResult.ok([]),
       session: nil,
       form: to_form(%{"content" => nil})
     })
     |> assign_async(:endpoint_available?, fn ->
       {:ok, %{endpoint_available?: AiAssistant.endpoint_available?()}}
     end)}
  end

  def update(%{action: action} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> apply_action(action, assigns)}
  end

  defp apply_action(socket, :new, %{selected_job: job}) do
    socket
    |> assign_async(:all_sessions, fn ->
      {:ok, %{all_sessions: AiAssistant.list_sessions_for_job(job)}}
    end)
  end

  defp apply_action(socket, :show, %{
         selected_job: job,
         chat_session_id: chat_session_id
       }) do
    if socket.assigns.process_message_on_show do
      message = hd(socket.assigns.session.messages)

      socket
      |> assign(:process_message_on_show, false)
      |> process_message(message.content)
    else
      session =
        chat_session_id
        |> AiAssistant.get_session!()
        |> AiAssistant.put_expression_and_adaptor(job.body, job.adaptor)

      socket
      |> assign(:session, session)
      |> assign(:process_message_on_show, false)
    end
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
          <%= case @action do %>
            <% :new -> %>
              <.render_sessions
                all_sessions={@all_sessions}
                query_params={@query_params}
                base_url={@base_url}
              />
            <% :show -> %>
              <.render_session
                session={@session}
                pending_message={@pending_message}
                query_params={@query_params}
                base_url={@base_url}
              />
          <% end %>
        </div>
        <.form
          for={@form}
          phx-submit="send_message"
          class="row-span-1 p-2 pt-0"
          phx-target={@myself}
          id="ai-assistant-form"
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
     |> save_message(socket.assigns.action, content)}
  end

  defp save_message(%{assigns: assigns} = socket, :new, content) do
    session =
      AiAssistant.create_session!(
        assigns.selected_job,
        assigns.current_user,
        content
      )

    query_params = Map.put(assigns.query_params, "chat", session.id)

    socket
    |> assign(:session, session)
    |> assign(:process_message_on_show, true)
    |> push_patch(to: redirect_url(assigns.base_url, query_params))
  end

  defp save_message(%{assigns: assigns} = socket, :show, content) do
    session =
      AiAssistant.save_message!(assigns.session, %{
        "role" => "user",
        "content" => content,
        "user_id" => assigns.current_user.id
      })

    socket
    |> assign(:session, session)
    |> process_message(content)
  end

  defp process_message(socket, message) do
    socket
    |> assign(:pending_message, AsyncResult.loading())
    |> start_async(
      :process_message,
      fn ->
        AiAssistant.query(socket.assigns.session, message)
      end
    )
  end

  defp redirect_url(base_url, query_params) do
    query_string =
      query_params
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> URI.encode_query()

    "#{base_url}?#{query_string}"
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
     |> update(:pending_message, fn async_result ->
       AsyncResult.failed(async_result, :error)
     end)}
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

  attr :all_sessions, AsyncResult, required: true
  attr :query_params, :map, required: true
  attr :base_url, :string, required: true

  defp render_sessions(assigns) do
    ~H"""
    <.async_result :let={all_sessions} assign={@all_sessions}>
      <:loading>
        <div class="row-span-full flex items-center justify-center">
          <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
            <.icon name="hero-sparkles" class="animate-pulse" />
          </div>
        </div>
      </:loading>
      <%= for session <- all_sessions do %>
        <.link
          patch={redirect_url(@base_url, Map.put(@query_params, "chat", session.id))}
          class="p-2 rounded-lg border border-gray-900 hover:bg-gray-100 flex items-center justify-between"
        >
          <span>
            <span class="inline-flex h-8 w-8 items-center justify-center rounded-full bg-gray-100">
              <span class="text-sm font-medium leading-none text-black uppercase">
                <%= String.first(session.user.first_name) %><%= String.first(
                  session.user.last_name
                ) %>
              </span>
            </span>
            <%= session.title %>
          </span>
          <%= session.updated_at %>
        </.link>
      <% end %>
    </.async_result>
    """
  end

  attr :session, AiAssistant.ChatSession, required: true
  attr :pending_message, AsyncResult, required: true
  attr :query_params, :map, required: true
  attr :base_url, :string, required: true

  defp render_session(assigns) do
    ~H"""
    <div class="sticky top-0 bg-gray-100 p-2 flex justify-between">
      <span><%= @session.title %></span>
      <.link patch={redirect_url(@base_url, Map.put(@query_params, "chat", nil))}>
        <.icon name="hero-x-mark" class="h-5 w-5" />
      </.link>
    </div>
    <%= for message <- @session.messages do %>
      <div
        :if={message.role == :user}
        class="ml-auto bg-blue-500 text-white p-2 rounded-lg text-right break-words"
      >
        <%= message.content %>
      </div>
      <div
        :if={message.role == :assistant}
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
    """
  end
end
