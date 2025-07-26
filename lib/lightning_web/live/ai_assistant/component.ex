defmodule LightningWeb.AiAssistant.Component do
  @moduledoc """
  Comprehensive LiveView component for AI-powered assistance in Lightning.

  This component provides a rich, interactive chat interface that integrates multiple
  AI assistance modes, real-time message processing, session management, and user
  experience optimizations. It serves as the primary user interface for all AI
  Assistant functionality within Lightning.
  """

  use LightningWeb, :live_component

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.Limiter
  alias LightningWeb.Live.AiAssistant.ModeRegistry
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  require Logger

  @dialyzer {:nowarn_function, process_ast: 2}

  def mount(socket) do
    {:ok,
     socket
     |> assign(%{
       session: nil,
       error_message: nil,
       ai_limit_result: nil,
       pagination_meta: nil,
       sort_direction: :desc,
       has_read_disclaimer: false,
       all_sessions: AsyncResult.ok([]),
       pending_message: AsyncResult.ok(nil),
       ai_enabled?: AiAssistant.enabled?(),
       workflow_error: nil,
       workflow_code: nil
     })
     |> assign_async(:endpoint_available?, fn ->
       {:ok, %{endpoint_available?: AiAssistant.endpoint_available?()}}
     end)}
  end

  def update(
        %{
          action: :workflow_parse_error,
          error_details: error_details,
          session_or_message: session_or_message
        },
        socket
      ) do
    message =
      case session_or_message do
        %AiAssistant.ChatSession{messages: messages} ->
          List.last(messages)

        %AiAssistant.ChatMessage{} = message ->
          message
      end

    {:ok,
     assign(socket,
       workflow_error: %{message: message, error: error_details}
     )}
  end

  def update(%{message_status_update: status}, socket) do
    updated_socket =
      case status do
        :processing ->
          assign(socket, :pending_message, AsyncResult.loading())

        {:completed, updated_session} ->
          socket
          |> assign(:session, updated_session)
          |> assign(:pending_message, AsyncResult.ok(nil))
          |> maybe_push_workflow_code(updated_session)
          |> assign(workflow_error: nil)

        :error ->
          session = socket.assigns.handler.get_session!(socket.assigns)

          socket
          |> assign(:session, session)
          |> assign(:pending_message, AsyncResult.ok(nil))
      end

    {:ok, updated_socket}
  end

  def update(
        %{action: action, current_user: current_user, mode: mode} = assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       has_read_disclaimer: AiAssistant.user_has_read_disclaimer?(current_user)
     )
     |> assign(:handler, ModeRegistry.get_handler(mode))
     |> assign_new(:changeset, fn %{handler: handler} ->
       handler.validate_form_changeset(%{"content" => nil})
     end)
     |> maybe_check_limit()
     |> apply_action(action)}
  end

  def render(assigns) do
    ~H"""
    <div id={@id} class="h-full relative">
      <%= if !@ai_enabled? do %>
        <.render_ai_not_configured />
      <% else %>
        <%= if !@has_read_disclaimer do %>
          <.render_onboarding
            myself={@myself}
            can_edit_workflow={@can_edit_workflow}
          />
        <% else %>
          <.render_session {assigns} />
        <% end %>
      <% end %>
    </div>
    """
  end

  def handle_event("validate", %{"assistant" => params}, socket) do
    handler = socket.assigns.handler

    {:noreply,
     assign(socket, changeset: handler.validate_form_changeset(params))}
  end

  def handle_event(
        "send_message",
        %{"assistant" => %{"content" => content} = params},
        socket
      ) do
    handler = socket.assigns.handler

    if socket.assigns.can_edit_workflow do
      %{action: action} = socket.assigns

      socket =
        socket
        |> assign(error_message: nil)
        |> check_limit()

      if socket.assigns.ai_limit_result == :ok do
        if handler.supports_template_generation?() do
          send_update(
            socket.assigns.parent_module,
            id: socket.assigns.parent_id,
            action: :sending_ai_message,
            content: content
          )
        end

        {:noreply,
         socket
         |> assign(
           :changeset,
           params
           |> Map.merge(%{"content" => nil})
           |> handler.validate_form_changeset()
         )
         |> assign(workflow_error: nil)
         |> save_message(action, content)}
      else
        {:noreply, socket}
      end
    else
      {:noreply,
       socket
       |> assign(
         changeset:
           params
           |> Map.merge(%{"content" => nil})
           |> handler.validate_form_changeset(),
         error_message: "You are not authorized to use the AI Assistant"
       )}
    end
  end

  def handle_event("mark_disclaimer_read", _params, socket) do
    {:ok, _} = AiAssistant.mark_disclaimer_read(socket.assigns.current_user)
    {:noreply, assign(socket, has_read_disclaimer: true)}
  end

  def handle_event("toggle_sort", _params, socket) do
    new_direction =
      if socket.assigns.sort_direction == :desc, do: :asc, else: :desc

    socket =
      socket
      |> assign(:sort_direction, new_direction)
      |> apply_action(:new)

    {:noreply, socket}
  end

  def handle_event("cancel_message", %{"message-id" => message_id}, socket) do
    message = Enum.find(socket.assigns.session.messages, &(&1.id == message_id))

    {:ok, session} =
      AiAssistant.update_message_status(
        socket.assigns.session,
        message,
        :cancelled
      )

    {:noreply, assign(socket, :session, session)}
  end

  def handle_event("retry_message", %{"message-id" => message_id}, socket) do
    message = Enum.find(socket.assigns.session.messages, &(&1.id == message_id))

    # Update status to pending so it gets picked up by Oban
    {:ok, _} =
      message
      |> Ecto.Changeset.change(%{status: :pending})
      |> Lightning.Repo.update()

    # Enqueue for processing
    Oban.insert(
      Lightning.Oban,
      Lightning.AiAssistant.MessageProcessor.new(%{
        message_id: message.id,
        session_id: socket.assigns.session.id
      })
    )

    # Update the session in the socket to reflect the status change
    {:ok, session} = AiAssistant.get_session(socket.assigns.session.id)

    {:noreply,
     socket
     |> assign(:session, session)
     |> assign(:pending_message, AsyncResult.loading())}
  end

  def handle_event(
        "select_assistant_message",
        %{"message-id" => message_id},
        %{assigns: assigns} = socket
      ) do
    message = Enum.find(assigns.session.messages, &(&1.id == message_id))
    {:noreply, maybe_push_workflow_code(socket, message)}
  end

  def handle_event("retry_load_sessions", _params, socket) do
    {:noreply, apply_action(socket, :new)}
  end

  def handle_event("load_more_sessions", _params, socket) do
    %{assigns: %{sort_direction: sort_direction, handler: handler} = assigns} =
      socket

    current_sessions =
      case socket.assigns.all_sessions do
        %AsyncResult{result: sessions} when is_list(sessions) -> sessions
        _ -> []
      end

    offset = length(current_sessions)

    socket =
      socket
      |> assign_async([:all_sessions, :pagination_meta], fn ->
        case handler.list_sessions(assigns, sort_direction,
               offset: offset,
               limit: 20
             ) do
          %{sessions: new_sessions, pagination: pagination} ->
            all_sessions = current_sessions ++ new_sessions
            {:ok, %{all_sessions: all_sessions, pagination_meta: pagination}}
        end
      end)

    {:noreply, socket}
  end

  defp apply_action(socket, :new) do
    %{assigns: %{sort_direction: sort_direction, handler: handler} = assigns} =
      socket

    ui_callback = fn event, _data ->
      case event do
        :clear_template ->
          if socket.assigns[:parent_module] ==
               LightningWeb.WorkflowLive.NewWorkflowComponent do
            send_update(
              socket.assigns.parent_module,
              id: socket.assigns.parent_id,
              action: :workflow_updated,
              workflow_code: nil,
              session_or_message: nil
            )
          else
            :ok
          end

        _ ->
          :ok
      end
    end

    socket
    |> handler.on_session_start(ui_callback)
    |> assign_async([:all_sessions, :pagination_meta], fn ->
      case handler.list_sessions(assigns, sort_direction, limit: 20) do
        %{sessions: sessions, pagination: pagination} ->
          {:ok, %{all_sessions: sessions, pagination_meta: pagination}}
      end
    end)
  end

  defp apply_action(socket, :show) do
    session = socket.assigns.handler.get_session!(socket.assigns)

    if socket.assigns[:parent_module] ==
         LightningWeb.WorkflowLive.NewWorkflowComponent do
      maybe_push_workflow_code(socket, session)
    end

    pending_message_loading =
      Enum.any?(session.messages, fn msg ->
        msg.role == :user && msg.status in [:pending, :processing]
      end)

    socket
    |> assign(:session, session)
    |> assign(
      :pending_message,
      if pending_message_loading do
        AsyncResult.loading()
      else
        AsyncResult.ok(nil)
      end
    )
  end

  defp save_message(socket, :new, content) do
    case socket.assigns.handler.create_session(socket.assigns, content) do
      {:ok, session} ->
        chat_param = get_chat_param_for_mode(socket.assigns.mode)

        query_params =
          Map.put(socket.assigns.query_params, chat_param, session.id)

        socket
        |> assign(:session, session)
        |> assign(:pending_message, AsyncResult.loading())
        |> push_patch(to: redirect_url(socket.assigns.base_url, query_params))

      error ->
        assign(socket,
          error_message: socket.assigns.handler.error_message(error)
        )
    end
  end

  defp save_message(socket, :show, content) do
    case socket.assigns.handler.save_message(socket.assigns, content) do
      {:ok, session} ->
        socket
        |> assign(:session, session)
        |> assign(:pending_message, AsyncResult.loading())

      error ->
        assign(socket,
          error_message: socket.assigns.handler.error_message(error)
        )
    end
  end

  defp redirect_url(base_url, query_params) do
    query_string =
      query_params
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> URI.encode_query()

    "#{base_url}?#{query_string}"
  end

  defp maybe_check_limit(%{assigns: %{ai_limit_result: nil}} = socket) do
    check_limit(socket)
  end

  defp maybe_check_limit(socket), do: socket

  defp check_limit(socket) do
    limit = Limiter.validate_quota(socket.assigns.project.id)

    error_message =
      if limit != :ok, do: socket.assigns.handler.error_message(limit)

    assign(socket, ai_limit_result: limit, error_message: error_message)
  end

  defp maybe_show_ellipsis(title) when is_binary(title) do
    if String.length(title) >= AiAssistant.title_max_length() do
      "#{title}..."
    else
      title
    end
  end

  defp display_cancel_message_btn?(session) do
    user_messages = Enum.filter(session.messages, &(&1.role == :user))
    length(user_messages) > 1
  end

  defp ai_feedback do
    Application.get_env(:lightning, :ai_feedback)
  end

  defp maybe_push_workflow_code(socket, session_or_message) do
    case socket.assigns.handler.extract_generated_code(session_or_message) do
      nil ->
        socket

      %{yaml: yaml} ->
        send_update(
          socket.assigns.parent_module,
          id: socket.assigns.parent_id,
          action: :workflow_updated,
          workflow_code: yaml,
          session_or_message: session_or_message
        )

        socket
    end
  end

  defp get_chat_param_for_mode(mode) do
    case mode do
      :workflow -> "w-chat"
      :job -> "j-chat"
      _ -> "chat"
    end
  end

  defp render_ai_not_configured(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-full">
      <div class="text-center w-1/2">
        <div class="mx-auto w-16 h-16 mb-6">
          <div class="w-16 h-16 rounded-full bg-gray-100 flex items-center justify-center">
            <.icon name="hero-cpu-chip" class="w-8 h-8 text-gray-400" />
          </div>
        </div>

        <h3 class="text-lg font-semibold text-gray-900 mb-4">
          AI Assistant Not Available
        </h3>

        <p class="text-gray-500 text-sm mb-4">
          AI Assistant has not been configured for your instance - contact your admin for support.
        </p>

        <p class="text-gray-500 text-sm mb-6">
          Try the AI Assistant on OpenFn cloud for free at
          <a
            href="https://app.openfn.org"
            target="_blank"
            class="text-primary-600 hover:text-primary-700 underline"
          >
            app.openfn.org
          </a>
        </p>

        <div class="text-xs text-gray-400 space-y-1">
          <p>To enable AI Assistant, your administrator needs to:</p>
          <ul class="list-disc list-inside text-left max-w-sm mx-auto mt-2 space-y-1">
            <li>Configure the Apollo endpoint URL</li>
            <li>Set up the AI Assistant API key</li>
            <li>Restart the Lightning application</li>
          </ul>
        </div>
      </div>
    </div>
    """
  end

  defp render_session(assigns) do
    ~H"""
    <div class="grid grid-cols-1 grid-rows-2 h-full flow-root bg-gray-50">
      <%= case @action do %>
        <% :new -> %>
          <.render_all_sessions
            all_sessions={@all_sessions}
            query_params={@query_params}
            base_url={@base_url}
            sort_direction={@sort_direction}
            pagination_meta={@pagination_meta}
            handler={@handler}
            target={@myself}
            mode={@mode}
          />
        <% :show -> %>
          <.render_individual_session
            session={@session}
            pending_message={@pending_message}
            query_params={@query_params}
            base_url={@base_url}
            target={@myself}
            handler={@handler}
            workflow_error={@workflow_error}
            mode={@mode}
          />
      <% end %>

      <.async_result :let={endpoint_available?} assign={@endpoint_available?}>
        <:loading>
          <div class="flex items-center justify-center m-4 border-r-2">
            <div class="rounded-full p-2 bg-indigo-200 text-indigo-700 ring-4 ring-gray-50">
              <.icon name="hero-sparkles" class="animate-pulse" />
            </div>
          </div>
        </:loading>

        <.form
          :let={form}
          as={:assistant}
          for={@changeset}
          phx-submit="send_message"
          phx-change="validate"
          class="row-span-1 pl-2 pr-2 pb-1"
          phx-target={@myself}
          phx-hook="SendMessageViaCtrlEnter"
          data-keybinding-scope="chat"
          id="ai-assistant-form"
        >
          <div
            :if={@error_message}
            id="ai-assistant-error"
            class="alert alert-danger hover:cursor-pointer flex justify-between"
            role="alert"
            phx-click={JS.hide()}
          >
            <div>{@error_message}</div>
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </div>

          <.chat_input
            form={form}
            disabled={
              @handler.chat_input_disabled?(%{
                assigns
                | endpoint_available?: endpoint_available?
              })
            }
            tooltip={@handler.disabled_tooltip_message(assigns)}
            handler={@handler}
          />
        </.form>
      </.async_result>
    </div>
    <.disclaimer />
    """
  end

  attr :disabled, :boolean
  attr :tooltip, :string
  attr :form, :map, required: true
  attr :handler, :any, required: true

  defp chat_input(assigns) do
    ~H"""
    <div class="mx-2 mb-2 mt-6">
      <div class={[
        "relative flex flex-col rounded-lg ring-1 transition-all duration-200",
        if(@disabled,
          do: "bg-gray-50 ring-gray-200 opacity-60",
          else:
            "bg-white ring-gray-200 focus-within:ring-2 focus-within:ring-indigo-600 focus-within:ring-offset-1 transition-shadow"
        )
      ]}>
        <label for="content" class="sr-only">Describe your request</label>

        <textarea
          id="content"
          name={@form[:content].name}
          rows="6"
          class={[
            "block w-full px-4 py-2 text-sm border-0 resize-none rounded-lg focus:outline-none focus:ring-0",
            if(@disabled,
              do:
                "bg-transparent text-gray-400 placeholder:text-gray-400 cursor-not-allowed",
              else: "bg-transparent text-gray-800 placeholder:text-gray-500"
            )
          ]}
          placeholder={
            if @disabled, do: @tooltip, else: @handler.input_placeholder()
          }
          disabled={@disabled}
          phx-hook="TabIndent"
        ><%= Phoenix.HTML.Form.normalize_value("textarea", @form[:content].value) %></textarea>

        <div
          class={[
            "flex items-center justify-end px-2 pt-2 pb-1 rounded-none rounded-b-lg",
            if(@disabled,
              do: "border-gray-200 bg-gray-50 cursor-not-allowed",
              else: "border-gray-200 bg-white cursor-text"
            )
          ]}
          phx-click={JS.focus(to: "#content")}
        >
          <span class={[
            "text-xs mr-2 font-bold",
            if(@disabled, do: "text-gray-400", else: "text-gray-500")
          ]}>
            <em>Do not paste PII or sensitive data</em>
          </span>

          <.simple_button_with_tooltip
            id="ai-assistant-form-submit-btn"
            type="submit"
            disabled={@disabled}
            form="ai-assistant-form"
            class={[
              "p-1.5 rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2 transition-all duration-200 flex items-center justify-center h-7 w-7",
              if(@disabled,
                do:
                  "text-gray-400 bg-gray-300 cursor-not-allowed focus:ring-gray-300",
                else:
                  "text-white bg-indigo-600 hover:bg-indigo-500 focus:ring-indigo-500"
              )
            ]}
          >
            <.icon name="hero-paper-airplane-solid" class="h-3 w-3" />
          </.simple_button_with_tooltip>
        </div>
      </div>

      <div
        :if={@handler.enable_attachment_options_component?()}
        class="mt-2 flex gap-2 content-center"
      >
        <span class="place-content-center">
          <.icon name="hero-paper-clip" class="size-4" /> Attach:
        </span>
        <.inputs_for :let={options} field={@form[:options]}>
          <.input type="checkbox" label="Code" field={options[:code]} />
          <%!-- <.input type="checkbox" label="Input" field={options[:input]} />
          <.input type="checkbox" label="Output" field={options[:output]} /> --%>
          <.input type="checkbox" label="Logs" field={options[:logs]} />
        </.inputs_for>
      </div>

      <div class="mt-2">
        <.ai_footer />
      </div>
    </div>
    """
  end

  attr :all_sessions, AsyncResult, required: true
  attr :query_params, :map, required: true
  attr :base_url, :string, required: true
  attr :sort_direction, :atom, required: true
  attr :pagination_meta, :any, default: nil
  attr :target, :string, required: true
  attr :mode, :atom, required: true
  attr :handler, :any, required: true

  defp render_all_sessions(assigns) do
    chat_param = get_chat_param_for_mode(assigns.mode)
    assigns = assign(assigns, :chat_param, chat_param)

    ~H"""
    <div class="row-span-full px-4 py-4 mb-2 overflow-y-auto">
      <.async_result :let={all_sessions} assign={@all_sessions}>
        <:loading>
          <div class="flex flex-col items-center justify-center py-8 m-4">
            <div class="rounded-full p-3 bg-indigo-100 text-indigo-600 ring-4 ring-gray-50">
              <.icon name="hero-sparkles" class="size-6 animate-pulse" />
            </div>
            <p class="mt-3 text-sm text-gray-600 font-medium">
              Loading chat history...
            </p>
            <p class="text-xs text-gray-500 mt-1">This may take a moment</p>
          </div>
        </:loading>

        <:failed :let={_failure}>
          <div class="text-center py-8">
            <div class="rounded-full p-3 bg-red-100 text-red-600 ring-4 ring-white mx-auto w-fit mb-3">
              <.icon name="hero-exclamation-triangle" class="size-6" />
            </div>
            <p class="text-red-700 font-medium">Failed to load chat history</p>
            <p class="text-sm text-gray-500 mt-1">
              Please check your connection and try again
            </p>
            <button
              phx-click="retry_load_sessions"
              phx-target={@target}
              class="mt-3 text-sm text-blue-600 hover:text-blue-800 hover:underline focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 rounded px-2 py-1 transition-colors duration-200"
            >
              Try again
            </button>
          </div>
        </:failed>

        <div :if={length(all_sessions) == 0} class="text-center py-12">
          <div class="rounded-full p-3 bg-gray-100 text-gray-400 mx-auto w-fit mb-4">
            <.icon name="hero-chat-bubble-left-right" class="size-8" />
          </div>
          <h3 class="text-lg font-medium text-gray-900 mb-2">No chat history yet</h3>
          <p class="text-gray-500 max-w-sm mx-auto">
            Start a conversation to see your chat history appear here. All your conversations will be saved automatically.
          </p>
        </div>

        <div :if={length(all_sessions) > 0}>
          <div class="mb-6 flex items-center justify-between">
            <div class="flex items-center gap-3">
              <h2 class="text-lg font-semibold text-gray-900">Chat History</h2>
              <.async_result :let={pagination} assign={@pagination_meta}>
                <span class="text-xs text-gray-500 bg-gray-200 px-2 py-1 rounded-full">
                  {length(all_sessions)} of {pagination.total_count}
                </span>
              </.async_result>
            </div>

            <button
              phx-click="toggle_sort"
              phx-target={@target}
              class="inline-flex items-center gap-1.5 px-3 py-1.5 text-sm text-gray-600 hover:text-gray-900 hover:bg-gray-50 rounded-md transition-colors duration-200 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
              aria-label={
                if @sort_direction == :desc,
                  do: "Currently showing latest first. Click to sort oldest first.",
                  else: "Currently showing oldest first. Click to sort latest first."
              }
            >
              <span>
                {if @sort_direction == :desc, do: "Latest", else: "Oldest"}
              </span>
              <%= if @sort_direction == :desc do %>
                <.icon name="hero-chevron-down" class="size-4" />
              <% else %>
                <.icon name="hero-chevron-up" class="size-4" />
              <% end %>
            </button>
          </div>

          <div class="space-y-3" role="list" aria-label="Chat sessions">
            <%= for session <- all_sessions do %>
              <.link
                id={"session-#{session.id}"}
                patch={
                  redirect_url(
                    @base_url,
                    Map.put(@query_params, @chat_param, session.id)
                  )
                }
                class="group bg-white block p-3 pb-1 rounded-lg border border-gray-200 hover:border-gray-300 hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 transition-all duration-200"
                role="listitem"
                aria-label={"Open chat: #{session.title}"}
              >
                <div class="flex items-start justify-between gap-3">
                  <div class="flex items-start space-x-3 min-w-0 flex-1">
                    <div class="flex-shrink-0 mt-0.5">
                      <.user_avatar user={session.user} />
                    </div>
                    <div class="min-w-0 flex-1">
                      <p class="text-sm font-medium text-gray-900 truncate group-hover:text-gray-700">
                        {maybe_show_ellipsis(@handler.chat_title(session))}
                      </p>
                      <p class="text-xs text-gray-500 mt-1">
                        {format_session_preview(session)}
                      </p>
                    </div>
                  </div>
                  <div class="flex-shrink-0 text-right">
                    <time
                      datetime={DateTime.to_iso8601(session.updated_at)}
                      class="text-xs text-gray-500 group-hover:text-gray-700 whitespace-nowrap block"
                    >
                      {time_ago(session.updated_at)}
                    </time>
                    <div class="mt-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200">
                      <.icon name="hero-chevron-right" class="size-4 text-gray-400" />
                    </div>
                  </div>
                </div>
              </.link>
            <% end %>
          </div>

          <.async_result :let={pagination} assign={@pagination_meta}>
            <div :if={pagination.has_next_page} class="mt-6 text-center">
              <button
                phx-click="load_more_sessions"
                phx-target={@target}
                class="inline-flex items-center gap-2 text-sm text-indigo-600 hover:text-indigo-800 hover:underline focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2 rounded px-3 py-2 transition-colors duration-200"
              >
                <span>Load more conversations</span>
                <span class="text-xs text-gray-500">
                  ({pagination.total_count - length(all_sessions)} remaining)
                </span>
              </button>
            </div>
          </.async_result>
        </div>
      </.async_result>
    </div>
    """
  end

  defp format_session_preview(session) do
    session
    |> get_preview_source()
    |> format_preview_text()
  end

  defp get_preview_source(session) do
    cond do
      has_message_count?(session) -> {:message_count, session.message_count}
      has_messages?(session) -> {:messages, length(session.messages)}
      has_last_message?(session) -> {:last_message, session.last_message}
      has_updated_at?(session) -> {:updated_at, session.updated_at}
      true -> {:default, nil}
    end
  end

  defp format_preview_text({:message_count, count}),
    do: format_message_count(count)

  defp format_preview_text({:messages, count}), do: format_message_count(count)

  defp format_preview_text({:last_message, message}),
    do: format_last_message(message)

  defp format_preview_text({:updated_at, datetime}),
    do: format_activity_status(datetime)

  defp format_preview_text({:default, _}), do: "Conversation"

  defp has_message_count?(session) do
    Map.has_key?(session, :message_count) and not is_nil(session.message_count)
  end

  defp has_messages?(session) do
    Map.has_key?(session, :messages) and is_list(session.messages)
  end

  defp has_last_message?(session) do
    Map.has_key?(session, :last_message) and not is_nil(session.last_message)
  end

  defp has_updated_at?(session) do
    Map.has_key?(session, :updated_at)
  end

  defp format_message_count(0), do: "New conversation"
  defp format_message_count(1), do: "1 message"
  defp format_message_count(count), do: "#{count} messages"

  defp format_last_message(message) do
    message
    |> String.trim()
    |> String.slice(0, 50)
    |> add_ellipsis_if_needed(String.length(message))
  end

  defp add_ellipsis_if_needed("", _), do: "New conversation"

  defp add_ellipsis_if_needed(preview, original_length)
       when original_length > 50 do
    preview <> "..."
  end

  defp add_ellipsis_if_needed(preview, _), do: preview

  defp format_activity_status(datetime) do
    if recent_activity?(datetime), do: "Recent activity", else: "Conversation"
  end

  defp recent_activity?(datetime) do
    Timex.diff(DateTime.utc_now(), datetime, :hours) < 1
  end

  defp render_onboarding(assigns) do
    assigns =
      assign(assigns,
        ai_quote: ai_quotes() |> Enum.filter(& &1[:enabled]) |> Enum.random()
      )

    ~H"""
    <div class="h-full flex flex-col">
      <div class="flex-1 flex flex-col items-center md:justify-center relative">
        <p class="text-gray-700 font-medium mb-8 w-1/2 text-center">
          The AI Assistant is a chat agent designed to help you write job code.
          <br /><br />
          Remember that you, the human in control, are responsible for how its output is used.
        </p>

        <.button
          theme="primary"
          id="get-started-with-ai-btn"
          phx-click="mark_disclaimer_read"
          phx-target={@myself}
          disabled={!@can_edit_workflow}
        >
          Get started with the AI Assistant
        </.button>

        <.disclaimer />
      </div>
      <.ai_footer />
    </div>
    """
  end

  defp ai_quotes do
    [
      %{
        quote: "What hath God wrought?",
        author: "Samuel Morse",
        source_attribute: "Samuel Morse in the first telegraph message",
        source_link: "https://www.history.com",
        enabled: true
      },
      %{
        quote: "All models are wrong, but some are useful",
        author: "George Box",
        source_attribute: "Wikipedia",
        source_link: "https://en.wikipedia.org/wiki/All_models_are_wrong",
        enabled: true
      },
      %{
        quote: "AI is neither artificial nor intelligent",
        author: "Kate Crawford",
        source_link:
          "https://www.wired.com/story/researcher-says-ai-not-artificial-intelligent/",
        enabled: true
      },
      %{
        quote: "With big data comes big responsibilities",
        author: "Kate Crawford",
        source_link:
          "https://www.technologyreview.com/2011/10/05/190904/with-big-data-comes-big-responsibilities",
        enabled: true
      },
      %{
        quote: "AI is holding the internet hostage",
        author: "Bryan Walsh",
        source_link:
          "https://www.vox.com/technology/352849/openai-chatgpt-google-meta-artificial-intelligence-vox-media-chatbots",
        enabled: true
      },
      %{
        quote: "Remember the human",
        author: "OpenFn Responsible AI Policy",
        source_link: "https://www.openfn.org/ai",
        enabled: true
      },
      %{
        quote: "Be skeptical, but don't be cynical",
        author: "OpenFn Responsible AI Policy",
        source_link: "https://www.openfn.org/ai",
        enabled: true
      },
      %{
        quote:
          "Out of the crooked timber of humanity no straight thing was ever made",
        author: "Emmanuel Kant",
        source_link:
          "https://www.goodreads.com/quotes/74482-out-of-the-crooked-timber-of-humanity-no-straight-thing"
      },
      %{
        quote:
          "The more helpful our phones get, the harder it is to be ourselves",
        author: "Brain Chrstian",
        source_attribute: "The most human Human",
        source_link:
          "https://www.goodreads.com/book/show/8884400-the-most-human-human"
      },
      %{
        quote:
          "If a machine can think, it might think more intelligently than we do, and then where should we be?",
        author: "Alan Turing",
        source_link:
          "https://turingarchive.kings.cam.ac.uk/publications-lectures-and-talks-amtb/amt-b-5"
      },
      %{
        quote:
          "If you make an algorithm, and let it optimise for a certain value, then it won't care what you really want",
        author: "Tom Chivers",
        source_link:
          "https://forum.effectivealtruism.org/posts/feNJWCo4LbsoKbRon/interview-with-tom-chivers-ai-is-a-plausible-existential"
      },
      %{
        quote:
          "By far the greatest danger of Artificial Intelligence is that people conclude too early that they understand it",
        author: "Eliezer Yudkowsky",
        source_attribute:
          "Artificial Intelligence as a Positive and Negative Factor in Global Risk",
        source_link:
          "https://zoo.cs.yale.edu/classes/cs671/12f/12f-papers/yudkowsky-ai-pos-neg-factor.pdf"
      },
      %{
        quote:
          "The AI does not hate you, nor does it love you, but you are made out of atoms which it can use for something else",
        author: "Eliezer Yudkowsky",
        source_attribute:
          "Artificial Intelligence as a Positive and Negative Factor in Global Risk",
        source_link:
          "https://zoo.cs.yale.edu/classes/cs671/12f/12f-papers/yudkowsky-ai-pos-neg-factor.pdf"
      },
      %{
        quote:
          "World domination is such an ugly phrase. I prefer to call it world optimisation",
        author: "Eliezer Yudkowsky",
        source_link: "https://hpmor.com/"
      },
      %{
        quote: "AI is not ultimately responsible for its output: we are",
        author: "OpenFn Responsible AI Policy",
        source_link: "https://www.openfn.org/ai"
      }
    ]
  end

  defp ai_footer(assigns) do
    ~H"""
    <div class="flex w-full">
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
          class="text-primary-400 hover:text-primary-600"
        >
          OpenFn Responsible AI Policy
        </a>
      </p>
    </div>
    """
  end

  attr :id, :string, default: "ai-assistant-disclaimer"

  defp disclaimer(assigns) do
    ~H"""
    <div id={@id} class="absolute inset-0 z-50 bg-white hidden">
      <div class="h-full w-full overflow-y-auto">
        <div class="bg-gray-50 p-4 flex justify-between border-solid border-b-1">
          <span class="font-medium text-gray-700">
            About the AI Assistant
          </span>
          <a href="#" phx-click={JS.hide(to: "##{@id}")}>
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </a>
        </div>
        <div class="p-4 text-sm flex flex-col gap-4">
          <p>
            The OpenFn AI Assistant provides a chat interface with an AI Model to help you build workflows. It can:
          </p>
          <ul class="list-disc list-inside pl-4">
            <li>Create a workflow template for you</li>
            <li>Draft job code for you</li>
            <li>Explain adaptor functions and how they are used</li>
            <li>Proofread and debug your job code</li>
            <li>Help understand why you are seeing an error</li>
          </ul>
          <p>
            Messages are saved unencrypted to the OpenFn database and may be monitored for quality control.
          </p>
          <h2 class="font-bold">
            Usage Tips
          </h2>
          <ul class="list-disc list-inside pl-4">
            <li>All chats are saved to the Project and can be viewed at any time</li>
            <li>Press <code>CTRL + ENTER</code> to send a message</li>
            <li>
              The Assistant can see your code and knows about OpenFn - just ask a question and don't worry too much about giving it context
            </li>
          </ul>
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
            The Assistant uses Claude Sonnet 3.7, by <a
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
            We do not send your input data, output data or logs to Anthropic.
          </p>
          <p>
            The Assistant uses a mixture of hand-written prompts and information
            from <a href="https://docs.openfn.org" target="none">docs.openfn.org</a>
            to inform its responses.
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

  attr :session, AiAssistant.ChatSession, required: true
  attr :pending_message, AsyncResult, required: true
  attr :query_params, :map, required: true
  attr :base_url, :string, required: true
  attr :target, :any, required: true
  attr :handler, :any, required: true
  attr :workflow_error, :any, required: true
  attr :mode, :atom, required: true

  defp render_individual_session(assigns) do
    assigns = assign(assigns, ai_feedback: ai_feedback())
    chat_param = get_chat_param_for_mode(assigns.mode)
    assigns = assign(assigns, :chat_param, chat_param)

    ~H"""
    <div class="row-span-full flex flex-col bg-gray-50">
      <div class="bg-white border-b border-gray-200 px-6 py-2 flex items-center justify-between sticky top-0 z-10">
        <div class="flex items-center gap-3 min-w-0 flex-1">
          <div class="flex-shrink-0">
            <div class="w-8 h-8 rounded-full ai-bg-gradient flex items-center justify-center">
              <.icon name="hero-chat-bubble-left-right" class="w-5 h-5 text-white" />
            </div>
          </div>
          <div class="min-w-0 flex-1">
            <h1 class="text-sm font-semibold text-gray-900 truncate">
              {maybe_show_ellipsis(@handler.chat_title(@session))}
            </h1>
            <p class="text-xs text-gray-500">
              {message_count_text(@session)} • {format_session_time(
                @session.updated_at
              )}
            </p>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <.link
            id="close-chat-session-btn"
            patch={redirect_url(@base_url, Map.put(@query_params, @chat_param, nil))}
            class="p-2 text-gray-400 hover:text-gray-600 hover:bg-gray-100 rounded-full transition-colors"
            phx-hook="Tooltip"
            aria-label="Click to close the current chat session"
          >
            <.icon name="hero-x-mark" class="w-6 h-6" />
          </.link>
        </div>
      </div>

      <div
        id={"ai-session-#{@session.id}-messages"}
        phx-hook="ScrollToMessage"
        data-scroll-to-message={
          if @workflow_error, do: @workflow_error.message.id, else: nil
        }
        class="flex-1 overflow-y-auto px-6 py-4 space-y-6"
      >
        <%= for message <- @session.messages do %>
          <%= if message.role == :user do %>
            <.user_message message={message} session={@session} target={@target} />
          <% else %>
            <.assistant_message
              message={message}
              handler={@handler}
              session={@session}
              target={@target}
              ai_feedback={@ai_feedback}
              workflow_error={@workflow_error}
              data-message-id={message.id}
            />
          <% end %>
        <% end %>

        <.async_result assign={@pending_message}>
          <:loading>
            <.assistant_typing_indicator handler={@handler} />
          </:loading>

          <:failed :let={failure}>
            <.assistant_error_message failure={failure} handler={@handler} />
          </:failed>
        </.async_result>
      </div>
    </div>
    """
  end

  defp user_message(assigns) do
    ~H"""
    <div class="flex text-sm justify-end">
      <div class="flex items-end gap-3 max-w-[85%]">
        <div :if={@message.status == :error} class="flex flex-col gap-1 mb-1">
          <button
            id={"retry-message-#{@message.id}"}
            phx-click="retry_message"
            phx-value-message-id={@message.id}
            phx-target={@target}
            class="w-7 h-7 rounded-full bg-white border border-gray-200 text-gray-500 hover:text-indigo-600 transition-all duration-200 flex items-center justify-center"
            phx-hook="Tooltip"
            aria-label="Retry this message"
          >
            <.icon name="hero-arrow-path" class="w-3.5 h-3.5" />
          </button>

          <button
            :if={display_cancel_message_btn?(@session)}
            id={"cancel-message-#{@message.id}"}
            phx-click="cancel_message"
            phx-value-message-id={@message.id}
            phx-target={@target}
            class="w-7 h-7 rounded-full bg-white border border-gray-200 text-gray-500 hover:text-red-600 transition-all duration-200 flex items-center justify-center"
            phx-hook="Tooltip"
            aria-label="Cancel this message"
          >
            <.icon name="hero-x-mark" class="w-3.5 h-3.5" />
          </button>
        </div>

        <div class={[
          "relative overflow-hidden rounded-2xl max-w-full",
          message_container_classes(@message.status)
        ]}>
          <div class="px-4 py-3">
            <p class={[
              "text-sm leading-relaxed",
              message_text_classes(@message.status)
            ]}>
              {@message.content}
            </p>
          </div>

          <div class={[
            "px-4 py-2 border-t flex items-center justify-between",
            message_footer_classes(@message.status)
          ]}>
            <span class={[
              "text-xs",
              message_timestamp_classes(@message.status)
            ]}>
              {format_message_time(@message.inserted_at)}
            </span>

            <div class="flex items-center gap-1">
              <%= case @message.status do %>
                <% :pending -> %>
                  <.icon name="hero-clock" class="w-3.5 h-3.5 text-indigo-300 ml-2" />
                  <span class="text-xs text-indigo-300">Sending</span>
                <% :error -> %>
                  <.icon
                    name="hero-exclamation-triangle"
                    class="w-3.5 h-3.5 text-red-300 ml-2"
                  />
                  <span class="text-xs text-red-300">Failed</span>
                <% _ -> %>
                  <.icon
                    name="hero-check-circle"
                    class="w-3.5 h-3.5 text-indigo-300 ml-2"
                  />
                  <span class="text-xs text-indigo-300">Sent</span>
              <% end %>
            </div>
          </div>
        </div>

        <div class="flex-shrink-0">
          <.user_avatar user={@message.user} size_class="w-8 h-8" />
        </div>
      </div>
    </div>
    """
  end

  defp assistant_message(assigns) do
    has_workflow_error? =
      assigns[:workflow_error] &&
        assigns.message.id == assigns.workflow_error.message.id

    assigns = assign(assigns, has_workflow_error?: has_workflow_error?)

    ~H"""
    <div class="text-sm flex justify-start" data-message-id={@message.id}>
      <div class="flex items-start gap-4 max-w-[85%]">
        <div class="flex-shrink-0 mt-1">
          <div class={[
            "w-8 h-8 rounded-full flex items-center justify-center",
            if(@has_workflow_error?,
              do: "bg-red-100",
              else: "ai-bg-gradient"
            )
          ]}>
            <.icon
              name={@handler.metadata().icon}
              class={[
                if(@has_workflow_error?,
                  do: "w-6 h-6 text-red-600",
                  else: "w-6 h-6 text-white"
                )
              ]}
            />
          </div>
        </div>

        <div
          class={[
            "flex-1 bg-white rounded-2xl border overflow-hidden",
            cond do
              @has_workflow_error? ->
                "border-red-300"

              @message.workflow_code && @handler.supports_template_generation?() ->
                "border-gray-200 cursor-pointer hover:border-indigo-200 transition-all duration-200 group"

              true ->
                "border-gray-200"
            end
          ]}
          {if @message.workflow_code && @handler.supports_template_generation?() && !@has_workflow_error?, do: [
            "phx-click": "select_assistant_message",
            "phx-value-message-id": @message.id,
            "phx-target": @target
          ], else: []}
        >
          <div
            :if={@has_workflow_error? && @message.workflow_code}
            class="px-4 py-2 bg-red-50 border-b border-red-200"
          >
            <div class="flex items-center gap-2">
              <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-red-600" />
              <p class="text-red-700 font-medium text-xs">
                Error while parsing workflow
              </p>
            </div>
          </div>

          <div
            :if={
              @message.workflow_code && @handler.supports_template_generation?() &&
                !@has_workflow_error?
            }
            class="px-4 py-2 ai-bg-gradient-light border-b border-gray-100"
          >
            <div class="flex items-center gap-2 text-sm">
              <.icon name="hero-gift" class="w-4 h-4 text-indigo-600" />
              <span class="text-indigo-700 font-medium text-xs">
                Click to restore workflow to here
              </span>
            </div>
          </div>

          <div class="px-4 py-4">
            <.formatted_content
              id={"message-#{@message.id}-content"}
              content={@message.content}
            />

            <div class="mt-3 pt-3 border-t border-gray-50 flex items-center justify-between">
              <div class="flex items-center gap-2">
                <span class="text-xs text-gray-500">
                  {format_message_time(@message.inserted_at)}
                </span>
              </div>

              <button
                id={"copy-message-#{@message.id}-content-btn"}
                type="button"
                class="text-xs text-gray-400 hover:text-gray-600 px-2 py-1 rounded hover:bg-gray-50 transition-colors"
                phx-hook="Copy"
                data-content={@message.content}
              >
                Copy
              </button>
            </div>
          </div>

          <div
            :if={@has_workflow_error? && @message.workflow_code}
            class="border-t border-red-100"
          >
            <button
              type="button"
              phx-click={
                JS.toggle(to: "#error-details-#{@message.id}")
                |> JS.toggle_class("rotate-180", to: "#error-chevron-#{@message.id}")
              }
              class="w-full px-4 py-2 flex items-center justify-between bg-red-50 transition-colors"
            >
              <span class="text-xs text-red-600">Click to view error details</span>
              <.icon
                id={"error-chevron-#{@message.id}"}
                name="hero-chevron-down"
                class="w-4 h-4 text-red-600 transition-transform"
              />
            </button>
            <div id={"error-details-#{@message.id}"} class="hidden px-4 py-4">
              <p class="text-red-600 text-xs">
                {@workflow_error.error}
              </p>
            </div>
          </div>

          <div :if={@ai_feedback && !@has_workflow_error?} class="px-4 pb-4">
            {Phoenix.LiveView.TagEngine.component(
              @ai_feedback.component,
              %{session_id: @session.id, message_id: @message.id},
              {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
            )}
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp assistant_typing_indicator(assigns) do
    ~H"""
    <div class="flex justify-start">
      <div class="flex items-start gap-4">
        <div class="flex-shrink-0 mt-1">
          <div class="w-8 h-8 rounded-full ai-bg-gradient flex items-center justify-center">
            <.icon name={@handler.metadata().icon} class="w-6 h-6 text-white" />
          </div>
        </div>

        <div class="bg-white rounded-2xl border border-gray-100 px-4 py-3">
          <div class="flex items-center gap-1">
            <div class="w-2 h-2 rounded-full bg-gray-400 animate-bounce"></div>
            <div
              class="w-2 h-2 rounded-full bg-gray-400 animate-bounce"
              style="animation-delay: 0.1s"
            >
            </div>
            <div
              class="w-2 h-2 rounded-full bg-gray-400 animate-bounce"
              style="animation-delay: 0.2s"
            >
            </div>
          </div>
          <p class="text-xs text-gray-500 mt-2">Processing...</p>
        </div>
      </div>
    </div>
    """
  end

  defp assistant_error_message(assigns) do
    ~H"""
    <div id="assistant-failed-message" class="flex justify-start">
      <div class="flex items-start gap-4 max-w-[85%]">
        <div class="flex-shrink-0 mt-1">
          <div class="w-8 h-8 rounded-full bg-red-100 flex items-center justify-center">
            <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-red-600" />
          </div>
        </div>

        <div class="bg-red-50 border border-red-200 rounded-2xl">
          <div class="px-4 py-3">
            <div class="flex items-start gap-3">
              <.icon
                name="hero-exclamation-triangle"
                class="w-5 h-5 text-red-500 flex-shrink-0 mt-0.5"
              />
              <div class="flex-1">
                <h4 class="text-sm font-medium text-red-800 mb-1">
                  Something went wrong
                </h4>
                <p class="text-sm text-red-700">
                  {@handler.error_message(@failure)}
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp message_container_classes(status) do
    case status do
      :success -> "ai-bg-gradient"
      :pending -> "ai-bg-gradient opacity-70"
      :error -> "ai-bg-gradient-error"
      _ -> "ai-bg-gradient"
    end
  end

  defp message_text_classes(status) do
    case status do
      :error -> "text-white"
      _ -> "text-white"
    end
  end

  defp message_footer_classes(status) do
    case status do
      :success -> "border-indigo-500/30 bg-black/5"
      :pending -> "border-indigo-400/30 bg-black/5"
      :error -> "border-red-400/30 bg-black/5"
      _ -> "border-indigo-500/30 bg-black/5"
    end
  end

  defp message_timestamp_classes(status) do
    case status do
      :error -> "text-red-200"
      _ -> "text-indigo-200"
    end
  end

  defp message_count_text(session) do
    case length(session.messages) do
      0 -> "No messages"
      1 -> "1 message"
      count -> "#{count} messages"
    end
  end

  defp format_session_time(datetime) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, datetime, :second)

    cond do
      diff_seconds < 60 -> "Just now"
      diff_seconds < 3600 -> "#{div(diff_seconds, 60)}m ago"
      diff_seconds < 86_400 -> "#{div(diff_seconds, 3600)}h ago"
      diff_seconds < 604_800 -> "#{div(diff_seconds, 86400)}d ago"
      true -> Calendar.strftime(datetime, "%b %d")
    end
  end

  defp format_message_time(datetime) do
    Calendar.strftime(datetime, "%I:%M %p")
  end

  attr :id, :string, required: true
  attr :content, :string, required: true
  attr :attributes, :map, default: %{}

  def formatted_content(assigns) do
    assistant_messages_attributes = %{
      "a" => %{
        class: "text-primary-400 hover:text-primary-600",
        target: "_blank"
      },
      "h1" => %{class: "text-2xl font-bold mb-6"},
      "h2" => %{class: "text-xl font-semibold mb-4 mt-8"},
      "ol" => %{class: "list-decimal pl-8 space-y-1"},
      "ul" => %{class: "list-disc pl-8 space-y-1"},
      "li" => %{class: "text-gray-800"},
      "p" => %{class: "mt-1 mb-2 text-gray-800"},
      "pre" => %{
        class:
          "rounded-md font-mono bg-slate-100 border-2 border-slate-200 text-slate-800 my-4 p-2 overflow-auto"
      }
    }

    merged_attributes =
      Map.merge(assistant_messages_attributes, assigns.attributes)

    assigns =
      case Earmark.Parser.as_ast(assigns.content) do
        {:ok, ast, _} ->
          process_ast(ast, merged_attributes) |> raw()

        _ ->
          assigns.content
      end
      |> then(&assign(assigns, :content, &1))

    ~H"""
    <article id={@id}>{@content}</article>
    """
  end

  defp process_ast(ast, attributes) do
    ast
    |> Earmark.Transform.map_ast(&process_node(&1, attributes))
    |> Earmark.Transform.transform()
  end

  defp process_node({element_type, attrs, _content, _meta} = node, attributes) do
    case Map.get(attributes, element_type) do
      nil -> node
      attribute_map -> apply_attributes(node, element_type, attrs, attribute_map)
    end
  end

  defp process_node(other, _attributes), do: other

  defp apply_attributes(node, "code", attrs, attribute_map) do
    case find_class_attr(attrs) do
      {_, [lang]} ->
        trimmed_lang = String.trim(lang)
        Earmark.AstTools.merge_atts_in_node(node, class: trimmed_lang)

      _ ->
        Earmark.AstTools.merge_atts_in_node(node, attribute_map)
    end
  end

  defp apply_attributes(node, _element_type, _attrs, attribute_map) do
    Earmark.AstTools.merge_atts_in_node(node, attribute_map)
  end

  defp find_class_attr(attrs) do
    Enum.find(attrs, fn {attr, _} -> attr == "class" end)
  end

  attr :user, Lightning.Accounts.User, required: true
  attr :size_class, :string, default: "h-8 w-8"

  defp user_avatar(assigns) do
    ~H"""
    <span class={"inline-flex #{@size_class} items-center justify-center rounded-full bg-gray-100 "}>
      <span
        class="text-sm leading-none text-black uppercase select-none"
        title={"#{@user.first_name} #{@user.last_name}"}
      >
        {String.first(@user.first_name)}{String.first(@user.last_name)}
      </span>
    </span>
    """
  end

  defp time_ago(datetime) do
    Timex.from_now(datetime)
  end
end
