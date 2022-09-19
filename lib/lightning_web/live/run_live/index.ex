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
    |> assign(:run, Invocation.get_run_with_job!(id))
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
          <b>Job:</b> <%= @run.job.name %>
        </.p>
        <br />
        <.p>
          <b>Logs</b>
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

  def run_time(assigns) do
    run = assigns[:run]

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

  # Expanded
  def first_example(assigns) do

    workflows = [%{
      name: "first workflow",
      last_run: "yesterday",
      dataclip_id: Ecto.UUID.generate() |> String.slice(0..5),
      status: "success"

      # list of workflow job statuses
      job_status: [
        %{
          status: "success", run_at: "right now", jobs: [
            %{name: "Kobo Submissions", status: "success"},
            %{name: "Upload to Googlesheets", status: "success"},
            %{name: "Upload to DHIS2", status: "success"}
          ]
        }
      ]
    }]

    # now we know that we can use `@expanded`
    assigns =
      assigns
      |> assign_new(:expanded, fn -> false end)
      |> assign(:workflows, workflows)

    ~H"""
    <tr class="my-4 grid grid-cols-4 gap-4 rounded-lg bg-white">
      <th
        scope="row"
        class="my-auto whitespace-nowrap p-6 font-medium text-gray-900 dark:text-white"
      >
        workFlowName
      </th>
      <td class="my-auto p-6">⭐ my-test-a</td>
      <td class="my-auto p-6">UTC 24:20:60</td>
      <td class="my-auto p-6">
        <div class="flex content-center justify-between">
          <span class="my-auto whitespace-nowrap rounded-full bg-green-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-green-800">
            Success
          </span>

          <button class="w-auto rounded-full bg-gray-50 p-3">
            <Heroicons.Outline.chevron_down class="h-5 w-5" />
          </button>
        </div>
      </td>
      <%= if @expanded do %>
      ghgfhgfhgfh
    <% end %>
      <td class="col-span-4 mx-3 mb-3 rounded-lg bg-gray-100 p-6">
        <ul class="list-inside list-none space-y-4 text-gray-500 dark:text-gray-400">
          <li>
            <span class="flex items-center">
              <Heroicons.Solid.clock class="mr-1 h-5 w-5" />

              <span>
                Re-run at 15 June 14:20:42
                <span class="my-auto ml-2 whitespace-nowrap rounded-full bg-green-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-green-800">
                  Success
                </span>
              </span>
            </span>
            <ol class="mt-2 list-none space-y-4">
              <%= if @expanded do %>
                ghgfhgfhgfh
              <% end %>
              <li>
                <span class="my-4 flex">
                  &vdash;
                  <span class="mx-2 flex">
                    <Heroicons.Solid.check_circle class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400" />
                    You might feel like you are being
                  </span>
                </span>
                <ol class="space-y-4 pl-5">
                  <li>
                    <span class="mx-1 flex">
                      &vdash;
                      <span class="ml-1">
                        are being really "organized" o
                      </span>
                    </span>
                  </li>
                </ol>
              </li>
              <li>
                <span class="flex">
                  &vdash;
                  <span class="mx-2 flex">
                    <Heroicons.Solid.check_circle class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400" />
                    You might feel like you are being
                  </span>
                </span>
              </li>
              <li>
                <span class="flex">
                  &vdash;
                  <span class="mx-2 flex">
                    <Heroicons.Solid.check_circle class="mr-1.5 h-5 w-5 flex-shrink-0 text-green-500 dark:text-green-400" />
                    You might feel like you are being
                  </span>
                </span>
              </li>
            </ol>
          </li>
        </ul>
      </td>
      <td class="col-span-4 mx-3 mb-3 rounded-lg bg-gray-100 p-6">
        <ul>
          <li>
            <span class="flex items-center">
              <Heroicons.Solid.clock class="mr-1 h-5 w-5" />

              <span>
                Run at 15 June 14:20:42
                <span class="my-auto ml-2 whitespace-nowrap rounded-full bg-red-200 py-2 px-4 text-center align-baseline text-xs font-medium leading-none text-red-800">
                  Failure
                </span>
              </span>
            </span>
          </li>
        </ul>
      </td>
    </tr>
    """
  end
end
