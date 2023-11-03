defmodule LightningWeb.AttemptLive.Show do
  use LightningWeb, :live_view

  alias Lightning.Attempts
  alias Lightning.Repo
  alias Phoenix.LiveView.AsyncResult

  import LightningWeb.AttemptLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <.async_result :let={attempt} assign={@attempt}>
          <:loading>
            <.loading_filler />
          </:loading>
          <:failed :let={_reason}>
            there was an error loading the attemptanization
          </:failed>

          <.detail_list>
            <.list_item>
              <:label>Attempt ID</:label>
              <:value><%= String.slice(attempt.id, 0..7) %></:value>
            </.list_item>
            <.list_item>
              <:label>Elapsed time</:label>
              <:value>7s</:value>
            </.list_item>
            <.list_item>
              <:label>Exit reason</:label>
              <:value>Running...</:value>
            </.list_item>
          </.detail_list>

          <.async_result :let={_has_log_lines} assign={@log_lines}>
            <:loading>
              <.loading_filler />
            </:loading>
            <:failed :let={_reason}>
              there was an error loading the log lines
            </:failed>
            <div
              phx-hook="LogLineHighlight"
              id={"attempt-log-#{attempt.id}"}
              data-selected-run-id={@selected_run_id}
            >
              <.log_view id={attempt.id} stream={@streams.log_lines} class="mt-4" />
            </div>
          </.async_result>
        </.async_result>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       page_title: "Attempt",
       selected_run_id: nil
     )
     |> stream(:log_lines, [])
     |> assign(:attempt, AsyncResult.loading())
     |> assign(:log_lines, AsyncResult.loading())
     |> start_async(:attempt, fn -> Attempts.get(id) end)}
  end

  @impl true
  def handle_params(params, _, socket) do
    selected_run_id = Map.get(params, "r")
    {:noreply, socket |> assign(:selected_run_id, selected_run_id)}
  end

  def handle_async(:attempt, {:ok, updated_attempt}, socket) do
    %{attempt: attempt} = socket.assigns

    Attempts.subscribe(updated_attempt)

    {:noreply,
     socket
     |> assign(attempt: AsyncResult.ok(attempt, updated_attempt))
     |> start_async(
       :log_lines,
       fn ->
         {:ok, lines} =
           Repo.transaction(fn ->
             Attempts.get_log_lines(updated_attempt)
             |> Enum.reverse()
           end)

         lines
       end
     )}
  end

  def handle_async(:attempt, {:exit, reason}, socket) do
    %{attempt: attempt} = socket.assigns

    {:noreply,
     assign(socket, :attempt, AsyncResult.failed(attempt, {:exit, reason}))}
  end

  def handle_async(:log_lines, {:ok, retrieved_log_lines}, socket) do
    %{log_lines: log_lines} = socket.assigns

    socket =
      socket
      |> stream(:log_lines, retrieved_log_lines, at: 0)
      |> assign(
        :log_lines,
        AsyncResult.ok(
          log_lines,
          socket.assigns.streams.log_lines.inserts |> Enum.any?()
        )
      )

    {:noreply, socket}
  end

  def loading_filler(assigns) do
    ~H"""
    <.detail_list class="animate-pulse">
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-16">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-24"></span>
        </:value>
      </.list_item>
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12"></span>
        </:value>
      </.list_item>
      <.list_item>
        <:label>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-12">&nbsp;</span>
        </:label>
        <:value>
          <span class="inline-block bg-slate-500 rounded-full h-3 w-24"></span>
        </:value>
      </.list_item>
    </.detail_list>
    """
  end
end
