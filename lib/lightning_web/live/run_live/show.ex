defmodule LightningWeb.RunLive.Show do
  @moduledoc """
  Show page for individual runs.
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation.Run

  import Ecto.Query
  import LightningWeb.RunLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(active_menu_item: :runs, page_title: "Run")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :show, %{"id" => id}) do
    run = from(r in Run, where: r.id == ^id) |> Lightning.Repo.one()

    socket |> assign(run: run)
  end

  @impl true
  def render(%{run: run} = assigns) do
    run_finished_at =
      if run.finished_at do
        run.finished_at |> Calendar.strftime("%c")
      end

    ran_for =
      if run.finished_at do
        DateTime.diff(run.finished_at, run.started_at, :millisecond)
      end

    # Format the log lines replacing single spaces with non-breaking spaces.
    log_lines =
      run.log ||
        []
        |> Enum.with_index()
        |> Enum.map(fn {line, num} ->
          {line |> spaces_to_nbsp(),
           (num + 1) |> to_string() |> String.pad_leading(3) |> spaces_to_nbsp()}
        end)

    assigns =
      assigns
      |> assign(
        log: log_lines,
        run_finished_at: run_finished_at,
        ran_for: ran_for
      )

    ~H"""
    <Layout.page_content>
      <:header>
        <Layout.header socket={@socket} title={@page_title} />
      </:header>
      <Layout.centered>
        <div class="flex flex-row" id={"finished-at-#{@run.id}"}>
          <div class="basis-3/4 font-semibold text-secondary-700">Finished</div>
          <div class="basis-1/4 text-right"><%= @run_finished_at %></div>
        </div>
        <div class="flex flex-row" id={"ran-for-#{@run.id}"}>
          <div class="basis-3/4 font-semibold text-secondary-700">Ran for</div>
          <div class="basis-1/4 text-right"><%= @ran_for %>ms</div>
        </div>
        <div class="flex flex-row" id={"exit-code-#{@run.id}"}>
          <div class="basis-3/4 font-semibold text-secondary-700">Exit Code</div>
          <div class="basis-1/4 text-right">
            <%= case @run.exit_code do %>
              <% val when val > 0-> %>
                <.failure_pill class="font-mono font-bold"><%= val %></.failure_pill>
              <% val when val == 0 -> %>
                <.success_pill class="font-mono font-bold">0</.success_pill>
              <% _ -> %>
            <% end %>
          </div>
        </div>
        <style>
          div.line-num::before { content: attr(data-line-number); padding-left: 0.1em; max-width: min-content; }
        </style>
        <div class="rounded-md mt-4 text-slate-200 bg-slate-700 border-slate-300 shadow-sm
                    font-mono proportional-nums w-full">
          <%= for { line, i } <- @log do %>
            <div class="group flex flex-row hover:bg-slate-600
              first:hover:rounded-tr-md first:hover:rounded-tl-md
              last:hover:rounded-br-md last:hover:rounded-bl-md ">
              <div
                data-line-number={i}
                class="line-num grow-0 border-r border-slate-500 align-top
                pr-2 text-right text-slate-400 inline-block
                group-hover:text-slate-300 group-first:pt-2 group-last:pb-2"
              >
              </div>
              <div class="grow pl-2 group-first:pt-2 group-last:pb-2">
                <pre class="whitespace-pre-line break-all"><%= line %></pre>
              </div>
            </div>
          <% end %>
        </div>
      </Layout.centered>
    </Layout.page_content>
    """
  end

  defp spaces_to_nbsp(str) when is_binary(str) do
    str
    |> String.codepoints()
    |> Enum.map(fn
      " " -> raw("&nbsp;")
      c -> c
    end)
  end
end
