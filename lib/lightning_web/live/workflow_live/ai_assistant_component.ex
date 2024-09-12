defmodule LightningWeb.WorkflowLive.AiAssistantComponent do
  use LightningWeb, :live_component

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.Limiter
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  def mount(socket) do
    {:ok,
     socket
     |> assign(%{
       ai_limit_result: nil,
       pending_message: AsyncResult.ok(nil),
       process_message_on_show: false,
       all_sessions: AsyncResult.ok([]),
       session: nil,
       form: to_form(%{"content" => nil}),
       error_message: nil
     })
     |> assign_async(:endpoint_available?, fn ->
       {:ok, %{endpoint_available?: AiAssistant.endpoint_available?()}}
     end)}
  end

  def update(%{action: action} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> maybe_check_limit()
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
    <div id={@id} class="h-full relative">
      <%= if @action == :new and !@has_read_disclaimer do %>
        <.render_onboarding myself={@myself} can_edit_workflow={@can_edit_workflow} />
      <% else %>
        <.render_session {assigns} />
      <% end %>
    </div>
    """
  end

  def handle_event("send_message", %{"content" => content}, socket) do
    if socket.assigns.can_edit_workflow do
      %{action: action} = socket.assigns
      # clear error
      socket
      |> assign(error_message: nil)
      |> check_limit()
      |> then(fn socket ->
        if socket.assigns.ai_limit_result == :ok do
          {:noreply, save_message(socket, action, content)}
        else
          {:noreply, socket}
        end
      end)
    else
      {:noreply,
       socket
       |> assign(
         form: to_form(%{"content" => nil}),
         error_message: "You are not authorized to use the Ai Assistant"
       )}
    end
  end

  def handle_event("mark_disclaimer_read", _params, socket) do
    {:noreply, assign(socket, has_read_disclaimer: true)}
  end

  defp save_message(%{assigns: assigns} = socket, :new, content) do
    case AiAssistant.create_session(
           assigns.selected_job,
           assigns.current_user,
           content
         ) do
      {:ok, session} ->
        query_params = Map.put(assigns.query_params, "chat", session.id)

        socket
        |> assign(:session, session)
        |> assign(:process_message_on_show, true)
        |> push_patch(to: redirect_url(assigns.base_url, query_params))

      error ->
        assign(socket, error_message: error_message(error))
    end
  end

  defp save_message(%{assigns: assigns} = socket, :show, content) do
    case AiAssistant.save_message(assigns.session, %{
           "role" => "user",
           "content" => content,
           "user" => assigns.current_user
         }) do
      {:ok, session} ->
        socket
        |> assign(:session, session)
        |> process_message(content)

      error ->
        assign(socket, error_message: error_message(error))
    end
  end

  defp error_message({:error, %Ecto.Changeset{}}) do
    "Oops! Could not save message. Please try again."
  end

  defp error_message({:error, :apollo_unavailable}) do
    "Oops! Could not reach the Ai Server. Please try again later."
  end

  defp error_message({:error, _reason, %{text: text_message}}) do
    text_message
  end

  defp error_message(_error) do
    "Oops! Something went wrong. Please try again."
  end

  defp process_message(socket, message) do
    session = socket.assigns.session

    socket
    |> assign(:pending_message, AsyncResult.loading())
    |> start_async(
      :process_message,
      fn -> AiAssistant.query(session, message) end
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

  def handle_async(:process_message, {:ok, error}, socket) do
    {:noreply,
     socket
     |> update(:pending_message, fn async_result ->
       AsyncResult.failed(async_result, error)
     end)}
  end

  def handle_async(:process_message, {:exit, error}, socket) do
    {:noreply,
     socket
     |> update(:pending_message, fn async_result ->
       AsyncResult.failed(async_result, {:exit, error})
     end)}
  end

  defp render_onboarding(assigns) do
    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex-1 flex flex-col items-center justify-center relative">
        <p class="text-gray-700 font-medium mb-4 w-1/2 text-center">
          The AI Assistant is an experimental new feature to help you write job code.
          <br />
          <br />
          Remember that you, the human in control, are responsible for how its output is used.
          <br />
        </p>

        <.button
          id="get-started-with-ai-btn"
          phx-click="mark_disclaimer_read"
          phx-target={@myself}
          disabled={!@can_edit_workflow}
        >
          Get started with the AI Assistant
        </.button>
        <.render_disclaimer />
      </div>
      <.render_ai_footer />
    </div>
    """
  end

  defp render_ai_footer(assigns) do
    ~H"""
    <div class="flex w-100">
      <p class="flex-1 text-xs mt-1 text-left ml-1">
        <a
          href="#"
          phx-click={JS.show(to: "#ai-assistant-disclaimer")}
          class="text-primary-400 hover:text-primary-600"
        >
          About the AI Assistant
        </a>
      </p>
      <p class="flex-1 text-xs mt-1 text-right mr-1">
        <a
          href="https://www.openfn.org/ai"
          target="_blank"
          phx-click={JS.show(to: "#ai-assistant-disclaimer")}
          class="text-primary-400 hover:text-primary-600"
        >
          OpenFn Responsible AI Policy
        </a>
      </p>
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
            About the AI Assistant
          </span>
          <a href="#" phx-click={JS.hide(to: "##{@id}")}>
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </a>
        </div>
        <div class="p-2 pt-4 text-sm flex flex-col gap-4">
          <p>
            The OpenFn AI Assistant provides a chat interface with an AI Model to help you build workflows. It can:
            <ul class="list-disc list-inside pl-4">
              <li>Draft job code for you</li>
              <li>Explain adaptor functions and how they are used</li>
              <li>Proofread and debug your job code</li>
              <li>Help understand why you are seeing an error</li>
            </ul>
          </p>

          <h2 class="font-bold">
            Using The Assistant Safely
          </h2>
          <p>
            The AI assistant uses a third-party model to process chat messages. Messages may be saved on OpenFn and Anthropic servers.
          </p>
          <p>
            Although we are constantly monitoring and improving the performance of the model, the Assistant can
            sometimes provide incorrect or misleading responses. You should consider the responses critically and verify
            the output where possible.
          </p>
          <p>
            Remember that all responses are generated by an algorithm, and you are responsible for how its output is used.
          </p>
          <p>
            Do not deploy autogenerated code in production environments without thorough testing.
          </p>
          <p>
            Do not include real user data, personally identifiable information, or sensitive business data in your queries.
          </p>
          <h2 class="font-bold">
            How it works
          </h2>
          <p>
            The Assistant uses Claude Sonnet 3.5, by <a
              href="https://www.anthropic.com/"
              target="_blank"
              class="text-primary-600"
            >Anthropic</a>, a Large Language Model (LLM) designed with a commitment to safety and privacy.
          </p>
          <p>
            Chat is saved with the Step and shared with all users with access to the Workflow.
            All collaborators within a project can see questions asked by other users.
          </p>
          <p>
            We include your step code in all queries sent to Claude, including some basic documentation,
            ensuring the model is well informed and can see what you can see.
            Note that we do not send input data or logs to Anthropic.
          </p>
          <h2 class="font-bold">Responsible AI Policy</h2>
          <p>
            Read about our approach to AI in the
            <a
              href="https://www.openfn.org/ai"
              target="_blank"
              class="text-primary-600"
            >
              OpenFn Responsible AI Policy
            </a>
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
          class="row-span-1 pl-2 pr-2 pb-1"
          phx-target={@myself}
          id="ai-assistant-form"
        >
          <div
            :if={@error_message}
            id="ai-assistant-error"
            class="alert alert-danger hover:cursor-pointer flex justify-between"
            role="alert"
            phx-click={JS.hide()}
          >
            <div><%= @error_message %></div>
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </div>
          <.chat_input
            form={@form}
            disabled={
              !@can_edit_workflow or has_reached_limit?(@ai_limit_result) or
                job_is_unsaved?(@selected_job) or
                !endpoint_available? or
                !is_nil(@pending_message.loading)
            }
            tooltip={
              disabled_tooltip_message(
                @can_edit_workflow,
                @ai_limit_result,
                @selected_job
              )
            }
          />
        </.form>
      </.async_result>
    </div>
    <.render_disclaimer />
    """
  end

  defp has_reached_limit?(ai_limit_result) do
    ai_limit_result != :ok
  end

  defp job_is_unsaved?(selected_job) do
    selected_job.__meta__.state == :built
  end

  defp disabled_tooltip_message(can_edit_workflow, ai_limit_result, selected_job) do
    case {can_edit_workflow, ai_limit_result, selected_job} do
      {false, _, _} ->
        "You are not authorized to use the Ai Assistant"

      {_, {:error, _reason, _msg} = error, _} ->
        error_message(error)

      {_, _, %{__meta__: %{state: :built}}} ->
        "Save the job first in order to use the AI Assistant"

      _ ->
        nil
    end
  end

  attr :disabled, :boolean
  attr :tooltip, :string
  attr :form, :map, required: true

  defp chat_input(assigns) do
    ~H"""
    <div class="text-xs text-center font-bold">
      Do not paste PII or sensitive business data
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
      <div class="py-2 pl-3 pr-2">
        <div class="flex items-center space-x-5"></div>
        <div class="flex-shrink-0">
          <.button
            id="ai-assistant-form-submit-btn"
            type="submit"
            disabled={@disabled}
            tooltip={@tooltip}
          >
            Send
          </.button>
        </div>
      </div>
    </div>
    <.render_ai_footer />
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
            id={"session-#{session.id}"}
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
          <div
            :if={message.role == :user}
            id={"message-#{message.id}"}
            class="ml-auto flex items-end gap-x-2"
          >
            <div class="bg-blue-300 bg-opacity-50 p-2 rounded-lg text-right break-words text-gray">
              <%= message.content %>
            </div>
            <.user_avatar user={message.user} size_class="min-w-7 h-7 w-7" />
          </div>
          <div
            :if={message.role == :assistant}
            id={"message-#{message.id}"}
            class="mr-auto p-2 rounded-lg break-words text-wrap flex flex-row gap-x-2 makeup-html"
          >
            <div>
              <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
                <.icon name="hero-cpu-chip" class="" />
              </div>
            </div>

            <div>
              <div>
                <%= message.content |> Earmark.as_html!() |> raw() %>
              </div>
              <!-- TODO: restore this message and add a link to the docs site -->
              <%!-- <div
                class="flex mt-1 text-xs text-gray-400 select-none"
                title="This message was generated using Claude, an LLM by Anthropic, and has not been verified by human experts"
              >
                Read, review and verify
              </div> --%>
            </div>
          </div>
        <% end %>
        <.async_result assign={@pending_message}>
          <:loading>
            <div
              id="assistant-pending-message"
              class="mr-auto p-2 rounded-lg break-words text-wrap flex flex-row gap-x-2 animate-pulse"
            >
              <div class="">
                <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
                  <.icon name="hero-sparkles" class="" />
                </div>
              </div>
              <div class="h-2 bg-slate-700 rounded"></div>
            </div>
          </:loading>
          <:failed :let={failure}>
            <div
              id="assistant-failed-message"
              class="mr-auto p-2 rounded-lg break-words text-wrap flex flex-row gap-x-2"
            >
              <div class="">
                <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-white">
                  <.icon name="hero-sparkles" class="" />
                </div>
              </div>
              <div class="flex gap-2">
                <.icon
                  name="hero-exclamation-triangle"
                  class="text-amber-400 h-8 w-8"
                />
                <span><%= error_message(failure) %></span>
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
    <span class={"inline-flex #{@size_class} items-center justify-center rounded-full bg-gray-100 "}>
      <span
        class="text-xs leading-none text-black uppercase select-none"
        title={"#{@user.first_name} #{@user.last_name}"}
      >
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

  defp maybe_check_limit(%{assigns: %{ai_limit_result: nil}} = socket) do
    check_limit(socket)
  end

  defp maybe_check_limit(socket), do: socket

  defp check_limit(socket) do
    %{project_id: project_id} = socket.assigns
    limit = Limiter.validate_quota(project_id)
    error_message = if limit != :ok, do: error_message(limit)
    assign(socket, ai_limit_result: limit, error_message: error_message)
  end
end
