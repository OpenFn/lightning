defmodule LightningWeb.WorkflowLive.AiAssistantComponent do
  use LightningWeb, :live_component
  alias Lightning.AiAssistant
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

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

  defp apply_action(socket, :new, %{selected_job: job} = assigns) do
    socket
    |> assign_async(:all_sessions, fn ->
      {:ok, %{all_sessions: AiAssistant.list_sessions_for_job(job)}}
    end)
    |> assign(has_read_disclaimer: assigns.project_has_chat_sessions)
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
    <div class="h-full">
      <%= if @action == :new and !@has_read_disclaimer do %>
        <.render_onboarding myself={@myself} can_edit_workflow={@can_edit_workflow} />
      <% else %>
        <.render_session {assigns} />
      <% end %>
    </div>
    """
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    {:noreply,
     socket
     |> save_message(socket.assigns.action, content)}
  end

  def handle_event("mark_disclaimer_read", _params, socket) do
    {:noreply, assign(socket, has_read_disclaimer: true)}
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
        "user" => assigns.current_user
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

  defp render_onboarding(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-full relative">
      <div class="text-center">
        <p class="text-gray-700 font-medium mb-4">
          All models are wrong. <br />- Joe Clark!
        </p>
        <p class="text-xs mb-2">
          <a
            href="#"
            phx-click={JS.show(to: "#ai-assistant-disclaimer")}
            class="text-primary-600"
          >
            Learn more about AI Assistant
          </a>
        </p>
        <.button
          id="get-started-with-ai-btn"
          phx-click="mark_disclaimer_read"
          phx-target={@myself}
          disabled={!@can_edit_workflow}
        >
          Get started with the AI Assistant
        </.button>
      </div>
      <.render_disclaimer />
    </div>
    """
  end

  attr :id, :string, default: "ai-assistant-disclaimer"

  defp render_disclaimer(assigns) do
    ~H"""
    <div id={@id} class="absolute inset-0 z-50 bg-white hidden">
      <div class="h-full w-full overflow-y-auto">
        <div class="bg-gray-100 p-2 flex justify-between border-solid border-t-2 border-b-2">
          <span class="font-medium text-gray-700">
            OpenFn AI Assistant Disclaimer
          </span>
          <a href="#" phx-click={JS.hide(to: "##{@id}")}>
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </a>
        </div>
        <div class="p-2 pt-4 text-sm flex flex-col gap-4">
          <div>
            <span class="font-medium">
              Introduction:
            </span>
            <p>
              OpenFn AI Assistant helps users to build workflows faster and better. Built on Claude Sonnet 3.5 from Anthropic, here are a few ways you can use the assistant to improve your job writing experience:
              <ul class="list-disc list-inside pl-4">
                <li>Prompt the AI to write a job for you</li>
                <li>Proofread and debug your job code</li>
                <li>Understand why you are seeing an error</li>
              </ul>
            </p>
          </div>
          <p>
            When you send a question to the AI, both the question and corresponding answer is stored with reference to the step. All collaborators within a project can see questions asked by other users.
          </p>
          <div>
            <span class="font-medium">
              Warning:
            </span>
            <p>
              The assistant can sometimes provide incorrect or misleading responses based on the model. We recommend that you check the responses before applying them on real life data.
            </p>
          </div>
          <p>
            Please do not include real life data with personally identifiable information or sensitive business data in your queries. OpenFn sends all queries to Anthropic for response and will not be liable for any exposure due to your prompts
          </p>

          <p>
            To learn more, please see our
            <a href="#" target="_blank" class="text-primary-600">
              Good Use of AI Policy
            </a>
            here.
          </p>
        </div>
      </div>
    </div>
    """
  end

  defp render_session(assigns) do
    ~H"""
    <div class="grid grid-cols-1 grid-rows-2 gap-4 h-full flow-root">
      <%= case @action do %>
        <% :new -> %>
          <.render_all_sessions
            all_sessions={@all_sessions}
            query_params={@query_params}
            base_url={@base_url}
          />
        <% :show -> %>
          <.render_individual_session
            session={@session}
            pending_message={@pending_message}
            query_params={@query_params}
            base_url={@base_url}
          />
      <% end %>

      <.async_result :let={endpoint_available?} assign={@endpoint_available?}>
        <:loading>
          <div class="row-span-full flex items-center justify-center">
            <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
              <.icon name="hero-sparkles" class="animate-pulse" />
            </div>
          </div>
        </:loading>
        <.form
          for={@form}
          phx-submit="send_message"
          class="row-span-1 p-2 pt-0"
          phx-target={@myself}
          id="ai-assistant-form"
        >
          <.chat_input
            form={@form}
            disabled={
              !endpoint_available? or !is_nil(@pending_message.loading) or
                !@can_edit_workflow
            }
          />
        </.form>
      </.async_result>
    </div>
    """
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
    <div class="text-xs text-center italic">
      Do not paste PPI or sensitive business data
    </div>
    <div class="w-full max-h-72 flex flex-row rounded-lg shadow-sm ring-1 ring-inset ring-gray-300 focus-within:ring-2 focus-within:ring-indigo-600">
      <label for={@form[:content].name} class="sr-only">
        Describe your request
      </label>
      <textarea
        id="content"
        name={@form[:content].name}
        class="block grow resize-none overflow-y-auto max-h-48 border-0 bg-transparent py-1.5 text-gray-900 placeholder:text-gray-400 placeholder:text-xs placeholder:italic focus:ring-0 text-sm"
        placeholder="Open a previous session or send a message to start a new session"
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

  defp render_all_sessions(assigns) do
    ~H"""
    <div class="row-span-full flex flex-col gap-4 p-2 overflow-y-auto">
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
            patch={
              redirect_url(@base_url, Map.put(@query_params, "chat", session.id))
            }
            class="p-2 rounded-lg border border-gray-900 hover:bg-gray-100 flex items-center justify-between"
          >
            <span>
              <.user_avatar user={session.user} />
              <%= session.title %>
            </span>
            <%= time_ago(session.updated_at) %>
          </.link>
        <% end %>
      </.async_result>
    </div>
    """
  end

  attr :session, AiAssistant.ChatSession, required: true
  attr :pending_message, AsyncResult, required: true
  attr :query_params, :map, required: true
  attr :base_url, :string, required: true

  defp render_individual_session(assigns) do
    ~H"""
    <div class="row-span-full overflow-y-auto">
      <div class="sticky top-0 bg-gray-100 p-2 flex justify-between border-solid border-t-2 border-b-2">
        <span class="font-medium"><%= @session.title %></span>
        <.link patch={redirect_url(@base_url, Map.put(@query_params, "chat", nil))}>
          <.icon name="hero-x-mark" class="h-5 w-5" />
        </.link>
      </div>
      <div class="flex flex-col gap-4 p-2 overflow-y-auto">
        <%= for message <- @session.messages do %>
          <div :if={message.role == :user} class="ml-auto flex items-end gap-x-2">
            <div class="bg-blue-300 bg-opacity-50 p-2 rounded-lg text-right break-words text-gray">
              <%= message.content %>
            </div>
            <.user_avatar user={message.user} size_class="min-w-7 h-7 w-7" />
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
      </div>
    </div>
    """
  end

  attr :user, Lightning.Accounts.User, required: true
  attr :size_class, :string, default: "h-8 w-8"

  defp user_avatar(assigns) do
    ~H"""
    <span class={"inline-flex #{@size_class} items-center justify-center rounded-full bg-gray-100"}>
      <span class="text-xs leading-none text-black uppercase">
        <%= String.first(@user.first_name) %><%= String.first(@user.last_name) %>
      </span>
    </span>
    """
  end

  # obtained from: https://medium.com/@obutemoses5/how-to-calculate-time-duration-in-elixir-33192bcfb62b
  defp time_ago(datetime) do
    minute = 60
    hour = minute * 60
    day = hour * 24
    week = day * 7
    month = day * 30
    year = day * 365

    diff = DateTime.utc_now() |> DateTime.diff(datetime)

    cond do
      diff >= year ->
        "#{Integer.floor_div(diff, year)} yr"

      diff >= month ->
        "#{Integer.floor_div(diff, month)} mo"

      diff >= week ->
        "#{Integer.floor_div(diff, week)} wk"

      diff >= day ->
        "#{Integer.floor_div(diff, day)} dy"

      diff >= hour ->
        "#{Integer.floor_div(diff, hour)} hr"

      diff >= minute ->
        "#{Integer.floor_div(diff, minute)} min"

      true ->
        "#{diff} sec"
    end
  end
end
