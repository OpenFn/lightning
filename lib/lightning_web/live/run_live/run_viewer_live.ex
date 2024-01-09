defmodule LightningWeb.RunLive.RunViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}

  alias LightningWeb.RunLive.Components
  alias Lightning.Attempts

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign(
        attempt_state:
          case assigns.attempt.state do
            :available -> "Pending"
            :claimed -> "Starting"
            :started -> "Running"
            :success -> "Success"
            :failed -> "Failed"
            :killed -> "Killed"
            :crashed -> "Crashed"
          end
      )

    ~H"""
    Status: <%= @attempt_state %> Attempt ID: <%= @attempt.id %>
    <%= @run && @run.id %>
    <table>
      <tbody id="log_lines" phx-update="stream">
        <tr :for={{dom_id, log_line} <- @streams.log_lines} id={dom_id}>
          <td>
            <Components.timestamp timestamp={log_line.timestamp} style={:time_only} />
          </td>
          <td><%= log_line.level %></td>
          <td><%= log_line.source %></td>
          <td><%= log_line.message %></td>
        </tr>
      </tbody>
    </table>
    """
  end

  @impl true
  def mount(_params, %{"attempt_id" => attempt_id}, socket) do
    attempt = Attempts.get(attempt_id)

    Attempts.subscribe(attempt)

    {:ok,
     socket
     |> assign(attempt: attempt, run: nil)
     |> stream(:log_lines, []), layout: false}
  end

  @impl true
  def handle_info(%Attempts.Events.RunStarted{run: _run}, socket) do
    # Use this to determine is the Job associated with the attempt is now running
    {:noreply, socket}
  end

  def handle_info(%Attempts.Events.AttemptUpdated{attempt: attempt}, socket) do
    {:noreply, socket |> assign(attempt: attempt)}
  end

  def handle_info(%Attempts.Events.LogAppended{log_line: log_line}, socket) do
    {:noreply, socket |> stream_insert(:log_lines, log_line)}
  end

  # Fallthrough in case there are events we don't care about.
  def handle_info(%{}, socket), do: {:noreply, socket}
end
