defmodule LightningWeb.RunLive.Index do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation
  alias Lightning.Invocation.Run

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       active_menu_item: :runs,
       pagination_path:
         &Routes.project_run_index_path(
           socket,
           :index,
           socket.assigns.project,
           &1
         )
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    socket
    |> assign(
      page_title: "Runs",
      run: %Run{},
      page: Invocation.list_runs_for_project(socket.assigns.project, params)
    )
  end

  defp apply_action(socket, :show, %{"id" => id}) do
    socket
    |> assign(:page_title, "Run")
    |> assign(:run, Invocation.get_run!(id))
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    run = Invocation.get_run!(id)
    {:ok, _} = Invocation.delete_run(run)

    {:noreply,
     socket
     |> assign(
       page: Invocation.list_runs_for_project(socket.assigns.project, %{})
     )}
  end

  def show_run(assigns) do
    ~H"""
    <.card>
      <.card_content
        heading={"Run #{@run.id}"}
        category={"Run exited with code #{@run.exit_code}"}
      >
        <.p>
          <b>Started:</b> <%= @run.started_at %>
        </.p>
        <.p>
          <b>Finished:</b> <%= @run.finished_at %>
        </.p>
        <.p>
          <b>Logs:</b>
        </.p>
        <div class="font-mono text-sm">
          <%= for line <- @run.log || [] do %>
            <li class="list-none">
              <%= raw(line |> String.replace(" ", "&nbsp;")) %>
            </li>
          <% end %>
        </div>
      </.card_content>
      <.card_footer>
        <%= live_redirect("Back",
          class:
            "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500",
          to: Routes.project_run_index_path(@socket, :index, @project.id)
        ) %>
      </.card_footer>
    </.card>
    """
  end

  # people: page.entries,
  # page_number: page.page_number,
  # page_size: page.page_size,
  # total_pages: page.total_pages,
  # total_entries: page.total_entries

  defp format_time(time) when is_nil(time) do
    ""
  end

  defp format_time(time) do
    time |> Timex.from_now(Timex.now(), "en")
  end

  def run_time(%{run: run} = assigns) do
    if run.finished_at do
      time_taken = Timex.diff(run.finished_at, run.started_at, :milliseconds)

      assigns =
        assigns
        |> assign(
          time_since: run.started_at |> format_time(),
          time_taken: time_taken
        )

      ~H"""
      <%= @time_since %> (<%= @time_taken %> ms)
      """
    else
      ~H"""

      """
    end
  end
end
