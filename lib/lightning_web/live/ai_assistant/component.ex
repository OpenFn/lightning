defmodule LightningWeb.AiAssistant.Component do
  @moduledoc """
  LiveView component for AI-powered assistance.

  Provides an interactive chat interface supporting multiple AI modes,
  real-time message processing, and session management.
  """
  use LightningWeb, :live_component

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.AiAssistant.Limiter
  alias LightningWeb.AiAssistant.Quotes
  alias LightningWeb.Live.AiAssistant.ModeRegistry
  alias Phoenix.LiveView.AsyncResult
  alias Phoenix.LiveView.JS

  require Logger

  @dialyzer {:nowarn_function, process_ast: 2}

  @default_page_size 20
  @message_preview_length 50
  @typing_animation_delay_ms 100

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(%{
       session: nil,
       ai_limit_result: nil,
       pagination_meta: nil,
       sort_direction: :desc,
       has_read_disclaimer: false,
       all_sessions: AsyncResult.ok([]),
       pending_message: AsyncResult.ok(nil),
       ai_enabled: AiAssistant.enabled?(),
       code: nil,
       code_error: nil,
       alert: nil,
       callbacks: %{},
       selected_message: nil,
       registered_session_id: nil,
       registered_component_id: nil
     })
     |> assign_async(:endpoint_available, fn ->
       {:ok, %{endpoint_available: AiAssistant.endpoint_available?()}}
     end)}
  end

  @impl true
  def update(%{message_status_changed: status}, socket) do
    {:ok, handle_message_status(status, socket)}
  end

  def update(%{action: :code_error} = assigns, socket) do
    {:ok, handle_code_error(socket, assigns)}
  end

  def update(%{action: action} = assigns, socket)
      when action in [:new, :show] do
    {:ok,
     socket
     |> init_assigns(assigns)
     |> register_session(assigns)
     |> ensure_limit_checked()
     |> apply_action(action)}
  end

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  defp register_session(socket, params) do
    registration = build_registration(params, socket)

    case registration do
      {:no_change, _} ->
        socket

      {:update, current, new} ->
        socket
        |> handle_unregistration(current, new)
        |> handle_registration(new)
        |> assign_registration(new)
    end
  end

  defp build_registration(params, socket) do
    new = %{
      session_id: params[:chat_session_id],
      component_id: params[:id] || params.id
    }

    current = %{
      session_id: socket.assigns[:registered_session_id],
      component_id: socket.assigns[:registered_component_id],
      has_pending: has_pending_operation?(socket)
    }

    if current.session_id == new.session_id &&
         current.component_id == new.component_id do
      {:no_change, current}
    else
      {:update, current, new}
    end
  end

  defp handle_unregistration(socket, %{session_id: nil}, _new), do: socket
  defp handle_unregistration(socket, %{has_pending: true}, _new), do: socket

  defp handle_unregistration(socket, current, new) do
    component_id = current.component_id || new.component_id
    send_unregister_message(component_id)
    socket
  end

  defp handle_registration(socket, %{session_id: nil}), do: socket

  defp handle_registration(socket, %{
         session_id: session_id,
         component_id: component_id
       }) do
    send_register_message(component_id, session_id)
    socket
  end

  defp assign_registration(socket, registration) do
    socket
    |> assign(:registered_session_id, registration.session_id)
    |> assign(:registered_component_id, registration.component_id)
  end

  defp has_pending_operation?(socket) do
    case socket.assigns[:pending_message] do
      %{loading: true} -> true
      %{loading: _} -> false
      _ -> false
    end
  end

  defp send_register_message(component_id, session_id) do
    send(self(), {
      :ai_assistant,
      :register_component,
      %{component_id: component_id, session_id: session_id}
    })
  end

  defp send_unregister_message(component_id) do
    send(self(), {
      :ai_assistant,
      :unregister_component,
      %{component_id: component_id}
    })
  end

  defp handle_message_status({:processing, session}, socket) do
    assign(socket,
      session: session,
      pending_message: AsyncResult.loading()
    )
  end

  defp handle_message_status({:success, session}, socket) do
    socket
    |> assign(
      session: session,
      pending_message: AsyncResult.ok(nil),
      selected_message: nil,
      code_error: nil
    )
    |> delegate_to_handler(:on_message_received, [session])
  end

  defp handle_message_status({:error, session}, socket) do
    assign(socket,
      session: session,
      pending_message: AsyncResult.ok(nil)
    )
  end

  defp handle_code_error(socket, assigns) do
    assign(socket,
      code_error: %{
        message_id: extract_message_id(assigns.session_or_message),
        details: assigns.error || "Unknown error"
      }
    )
  end

  defp init_assigns(socket, assigns) do
    handler = ModeRegistry.get_handler(assigns.mode)

    socket
    |> assign(assigns)
    |> assign(
      callbacks: assigns[:callbacks] || %{},
      handler: handler,
      has_read_disclaimer: AiAssistant.user_has_read_disclaimer?(assigns.user)
    )
    |> assign_new(:changeset, fn _ ->
      handler.validate_form(%{"content" => nil})
    end)
  end

  defp extract_message_id(%ChatSession{messages: messages}) do
    messages
    |> List.last()
    |> extract_message_id()
  end

  defp extract_message_id(%ChatMessage{id: id}), do: id
  defp extract_message_id(_), do: nil

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="h-full relative"><.render_content {assigns} /></div>
    """
  end

  defp render_content(%{ai_enabled: false} = assigns) do
    ~H"""
    <.render_ai_not_configured />
    """
  end

  defp render_content(%{has_read_disclaimer: false} = assigns) do
    ~H"""
    <.render_onboarding id={@id} myself={@myself} can_edit={@can_edit} />
    """
  end

  defp render_content(assigns) do
    ~H"""
    <.render_session {assigns} />
    """
  end

  @impl true
  def handle_event("validate", %{"assistant" => params}, socket) do
    handler = socket.assigns.handler

    {:noreply, assign(socket, changeset: handler.validate_form(params))}
  end

  def handle_event(
        "send_message",
        %{"assistant" => %{"content" => content} = params},
        socket
      ) do
    cleared_params = Map.put(params, "content", nil)
    trimmed_content = if is_binary(content), do: String.trim(content), else: ""

    cond do
      not socket.assigns.can_edit ->
        {:noreply,
         socket
         |> assign(
           changeset: socket.assigns.handler.validate_form(cleared_params),
           alert: "You are not authorized to use the AI Assistant"
         )}

      socket.assigns.ai_limit_result != :ok ->
        {:noreply, socket}

      trimmed_content == "" ->
        changeset = socket.assigns.handler.validate_form(%{"content" => ""})

        changeset =
          Ecto.Changeset.add_error(
            changeset,
            :content,
            "Please enter a message before sending"
          )

        {:noreply,
         socket
         |> assign(
           changeset: changeset,
           alert: "Please enter a message before sending"
         )}

      true ->
        {:noreply,
         socket
         |> assign(alert: nil, code_error: nil)
         |> delegate_to_handler(:on_message_send)
         |> assign(
           :changeset,
           socket.assigns.handler.validate_form(cleared_params)
         )
         |> save_message(socket.assigns.action, trimmed_content)}
    end
  end

  def handle_event("mark_disclaimer_read", _params, socket) do
    {:ok, _} = AiAssistant.mark_disclaimer_read(socket.assigns.user)
    {:noreply, assign(socket, has_read_disclaimer: true)}
  end

  def handle_event("toggle_sort", _params, socket) do
    {:noreply,
     socket
     |> update(:sort_direction, fn
       :desc -> :asc
       :asc -> :desc
     end)
     |> apply_action(:new)}
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
    socket.assigns.session.messages
    |> Enum.find(&(&1.id == message_id))
    |> AiAssistant.retry_message()
    |> case do
      {:ok, {_message, _oban_job}} ->
        {:ok, session} = AiAssistant.get_session(socket.assigns.session.id)

        {:noreply,
         socket
         |> assign(:session, session)
         |> assign(:pending_message, AsyncResult.loading())}

      {:error, _changeset} ->
        {:noreply,
         put_flash(socket, :error, "Failed to retry message. Please try again.")}
    end
  end

  def handle_event(
        "select_assistant_message",
        %{"message-id" => message_id},
        %{assigns: assigns} = socket
      ) do
    message = Enum.find(assigns.session.messages, &(&1.id == message_id))

    {:noreply,
     socket
     |> assign(selected_message: message)
     |> delegate_to_handler(:on_message_selected, [message])}
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

    {:noreply,
     socket
     |> assign_async([:all_sessions, :pagination_meta], fn ->
       case handler.list_sessions(assigns, sort_direction,
              offset: length(current_sessions),
              limit: @default_page_size
            ) do
         %{sessions: new_sessions, pagination: pagination} ->
           all_sessions = current_sessions ++ new_sessions
           {:ok, %{all_sessions: all_sessions, pagination_meta: pagination}}
       end
     end)}
  end

  defp apply_action(socket, action) do
    %{assigns: %{sort_direction: sort_direction, handler: handler} = assigns} =
      socket

    case action do
      :new ->
        socket
        |> delegate_to_handler(:on_session_close)
        |> assign_async([:all_sessions, :pagination_meta], fn ->
          case handler.list_sessions(assigns, sort_direction,
                 limit: @default_page_size
               ) do
            %{sessions: sessions, pagination: pagination} ->
              {:ok, %{all_sessions: sessions, pagination_meta: pagination}}
          end
        end)

      :show ->
        session = handler.get_session!(assigns)

        message_loading =
          Enum.any?(session.messages, fn msg ->
            msg.role == :user && msg.status in [:pending, :processing]
          end)

        socket
        |> assign(:session, session)
        |> assign(
          :pending_message,
          if message_loading do
            AsyncResult.loading()
          else
            AsyncResult.ok(nil)
          end
        )
        |> delegate_to_handler(:on_session_open, [session])
    end
  end

  defp save_message(socket, action, content) do
    result =
      case action do
        :new -> create_new_session(socket, content)
        :show -> add_to_existing_session(socket, content)
      end

    case result do
      {:ok, session} ->
        handle_successful_save(socket, session, action)

      {:error, error} ->
        handle_save_error(socket, error)
    end
  end

  defp create_new_session(socket, content) do
    socket.assigns.handler.create_session(socket.assigns, content)
  end

  defp add_to_existing_session(socket, content) do
    socket.assigns.handler.save_message(socket.assigns, content)
  end

  defp handle_successful_save(socket, session, :new) do
    socket
    |> assign(:session, session)
    |> assign(:pending_message, AsyncResult.loading())
    |> redirect_to_session(session)
  end

  defp handle_successful_save(socket, session, :show) do
    socket
    |> assign(:session, session)
    |> assign(:pending_message, AsyncResult.loading())
  end

  defp redirect_to_session(socket, session) do
    chat_param = socket.assigns.handler.metadata().chat_param
    query_params = Map.put(socket.assigns.query_params, chat_param, session.id)
    push_patch(socket, to: redirect_url(socket.assigns.base_url, query_params))
  end

  defp handle_save_error(socket, error) do
    socket
    |> assign(alert: socket.assigns.handler.error_message(error))
    |> assign(pending_message: AsyncResult.ok(nil))
  end

  defp redirect_url(base_url, query_params) do
    query_string =
      query_params
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> URI.encode_query()

    "#{base_url}?#{query_string}"
  end

  defp ensure_limit_checked(%{assigns: %{ai_limit_result: nil}} = socket) do
    limit = Limiter.validate_quota(socket.assigns.project.id)

    alert =
      if limit != :ok, do: socket.assigns.handler.error_message(limit), else: nil

    assign(socket, ai_limit_result: limit, alert: alert)
  end

  defp ensure_limit_checked(socket), do: socket

  defp delegate_to_handler(socket, callback, args \\ []) do
    handler = socket.assigns.handler

    if function_exported?(handler, callback, length(args) + 1) do
      apply(handler, callback, [socket | args])
    else
      socket
    end
  end

  defp maybe_show_ellipsis(title) when is_binary(title) do
    if String.length(title) >= AiAssistant.title_max_length() do
      "#{title}..."
    else
      title
    end
  end

  defp display_cancel_message_btn?(session) do
    session.messages |> Enum.filter(&(&1.role == :user)) |> length() > 1
  end

  defp ai_feedback do
    Application.get_env(:lightning, :ai_feedback)
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
            code_error={@code_error}
            mode={@mode}
          />
      <% end %>

      <.async_result :let={endpoint_available} assign={@endpoint_available}>
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
          id={"ai-assistant-form-#{@id}"}
        >
          <div
            :if={@alert}
            id="ai-assistant-error"
            class="alert alert-danger hover:cursor-pointer flex justify-between"
            role="alert"
            phx-click={JS.hide()}
          >
            <div>{@alert}</div>
            <.icon name="hero-x-mark" class="h-5 w-5" />
          </div>

          <.chat_input
            id={"chat-input-#{@id}"}
            disclaimer_id={"ai-assistant-disclaimer-#{@id}"}
            form_id={"ai-assistant-form-#{@id}"}
            form={form}
            disabled={
              @handler.chat_input_disabled?(%{
                assigns
                | endpoint_available: endpoint_available
              })
            }
            tooltip={@handler.disabled_tooltip_message(assigns)}
            handler={@handler}
          />
        </.form>
      </.async_result>
    </div>
    <.disclaimer id={"ai-assistant-disclaimer-#{@id}"} />
    """
  end

  attr :id, :string
  attr :disclaimer_id, :string
  attr :disabled, :boolean
  attr :tooltip, :string
  attr :form, :map, required: true
  attr :form_id, :string, required: true
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
          id={"content-#{@id}"}
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
            id={"ai-assistant-form-submit-btn-#{@id}"}
            type="submit"
            disabled={@disabled || form_content_empty?(@form[:content].value)}
            form={@form_id}
            class={[
              "p-1.5 rounded-full focus:outline-none focus:ring-2 focus:ring-offset-2 transition-all duration-200 flex items-center justify-center h-7 w-7",
              if(@disabled || form_content_empty?(@form[:content].value),
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

      <%= if form = @handler.render_config_form(assigns) do %>
        {form}
      <% end %>

      <div class="mt-2">
        <.ai_footer disclaimer_id={@disclaimer_id} />
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
    chat_param = assigns.handler.metadata().chat_param
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
                      <.user_avatar
                        id={"session-#{session.id}-avatar"}
                        user={session.user}
                      />
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
    |> String.slice(0, @message_preview_length)
    |> add_ellipsis_if_needed(String.length(message))
  end

  defp add_ellipsis_if_needed("", _), do: "New conversation"

  defp add_ellipsis_if_needed(preview, original_length)
       when original_length > @message_preview_length do
    preview <> "..."
  end

  defp add_ellipsis_if_needed(preview, _), do: preview

  defp format_activity_status(datetime) do
    if recent_activity?(datetime), do: "Recent activity", else: "Conversation"
  end

  defp recent_activity?(datetime) do
    Timex.diff(DateTime.utc_now(), datetime, :hours) < 1
  end

  defp form_content_empty?(value) do
    case value do
      nil -> true
      "" -> true
      content when is_binary(content) -> String.trim(content) == ""
      _ -> false
    end
  end

  defp render_onboarding(assigns) do
    assigns = assign(assigns, ai_quote: Quotes.random_enabled())

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
          disabled={!@can_edit}
        >
          Get started with the AI Assistant
        </.button>

        <.disclaimer id={"ai-assistant-disclaimer-#{@id}"} />
      </div>
      <.ai_footer disclaimer_id={"ai-assistant-disclaimer-#{@id}"} />
    </div>
    """
  end

  defp ai_footer(assigns) do
    ~H"""
    <div class="flex w-full">
      <p class="flex-1 text-xs mt-1 text-left ml-1">
        <a
          href="#"
          phx-click={JS.show(to: "##{@disclaimer_id}")}
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
            The AI assistant uses Claude by Anthropic, a third-party AI model.
            Messages are stored on OpenFn servers and temporarily on Anthropic servers (up to 30 days) but are not used to train AI models. <a
              href="https://privacy.claude.com/en/collections/10672411-data-handling-retention"
              target="_blank"
              class="text-primary-600 hover:text-primary-700"
            >
              Read more about this here
            </a>.
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
  attr :code_error, :any, required: true
  attr :mode, :atom, required: true

  defp render_individual_session(assigns) do
    assigns = assign(assigns, ai_feedback: ai_feedback())
    chat_param = assigns.handler.metadata().chat_param
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
              {message_count_text(@session)} &bull; {format_session_time(
                @session.updated_at
              )}
            </p>
          </div>
        </div>

        <div class="flex items-center gap-2">
          <.link
            id={"close-chat-session-btn-#{@session.id}"}
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
          if @code_error, do: @code_error.message_id, else: nil
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
              code_error={@code_error}
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
    msg_status = message_status_display(assigns.message.status)
    assigns = assign(assigns, msg_status: msg_status)

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
              <.icon
                name={@msg_status.icon}
                class={"w-3.5 h-3.5 #{@msg_status.color} ml-2"}
              />
              <span class={"text-xs #{@msg_status.color}"}>{@msg_status.text}</span>
            </div>
          </div>
        </div>

        <div class="flex-shrink-0">
          <.user_avatar
            id={"message-#{@message.id}-avatar"}
            user={@message.user}
            size_class="w-8 h-8"
          />
        </div>
      </div>
    </div>
    """
  end

  defp assistant_message(assigns) do
    code_error = assigns[:code_error]
    has_error = code_error && code_error.message_id == assigns.message.id
    assigns = assign(assigns, has_error: has_error)

    ~H"""
    <div class="text-sm flex justify-start" data-message-id={@message.id}>
      <div class="flex items-start gap-4 max-w-[85%]">
        <div class="flex-shrink-0 mt-1">
          <div class={[
            "w-8 h-8 rounded-full flex items-center justify-center",
            if(@has_error,
              do: "bg-red-100",
              else: "ai-bg-gradient"
            )
          ]}>
            <.icon
              name={@handler.metadata().icon}
              class={[
                if(@has_error,
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
              @has_error ->
                "border-red-300"

              @message.code ->
                "border-gray-200 cursor-pointer hover:border-indigo-200 transition-all duration-200 group"

              true ->
                "border-gray-200"
            end
          ]}
          {if @message.code && !@has_error, do: [
            "phx-click": "select_assistant_message",
            "phx-value-message-id": @message.id,
            "phx-target": @target
          ], else: []}
        >
          <div :if={@has_error} class="px-4 py-2 bg-red-50 border-b border-red-200">
            <div class="flex items-center gap-2">
              <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-red-600" />
              <p class="text-red-700 font-medium text-xs">
                Error while parsing workflow
              </p>
            </div>
          </div>

          <div
            :if={@message.code && !@has_error}
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

          <div :if={@has_error} class="border-t border-red-100">
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
                {@code_error.details}
              </p>
            </div>
          </div>

          <div :if={@ai_feedback} class="px-4 pb-4">
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
    assigns = assign(assigns, animation_delay: @typing_animation_delay_ms)

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
              style={"animation-delay: #{@animation_delay}ms"}
            >
            </div>
            <div
              class="w-2 h-2 rounded-full bg-gray-400 animate-bounce"
              style={"animation-delay: #{@animation_delay * 2}ms"}
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

  defp message_status_display(:pending),
    do: %{icon: "hero-clock", text: "Sending", color: "text-indigo-300"}

  defp message_status_display(:error),
    do: %{
      icon: "hero-exclamation-triangle",
      text: "Failed",
      color: "text-red-300"
    }

  defp message_status_display(_),
    do: %{icon: "hero-check-circle", text: "Sent", color: "text-indigo-300"}

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

  attr :user, Lightning.Accounts.User, default: nil
  attr :size_class, :string, default: "h-8 w-8"
  attr :id, :string, default: nil

  defp user_avatar(%{user: nil} = assigns) do
    ~H"""
    <span class={"inline-flex #{@size_class} items-center justify-center rounded-full bg-gray-100 "}>
      <span class="text-sm leading-none text-gray-400 uppercase select-none">
        ?
      </span>
    </span>
    """
  end

  defp user_avatar(assigns) do
    first_initial = get_initial(assigns.user.first_name)
    last_initial = get_initial(assigns.user.last_name)
    full_name = build_user_title(assigns.user.first_name, assigns.user.last_name)

    assigns =
      assign(assigns,
        first_initial: first_initial,
        last_initial: last_initial,
        full_name: full_name
      )

    ~H"""
    <span
      id={@id}
      class={"inline-flex #{@size_class} items-center justify-center rounded-full bg-gray-100 cursor-default"}
      phx-hook="Tooltip"
      aria-label={@full_name}
    >
      <span class="text-sm leading-none text-black uppercase select-none">
        {@first_initial}{@last_initial}
      </span>
    </span>
    """
  end

  defp get_initial(nil), do: ""
  defp get_initial(""), do: ""
  defp get_initial(name) when is_binary(name), do: String.first(name)
  defp get_initial(_), do: ""

  defp build_user_title(first_name, last_name) do
    [first_name, last_name]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  defp time_ago(datetime) do
    Timex.from_now(datetime)
  end
end
