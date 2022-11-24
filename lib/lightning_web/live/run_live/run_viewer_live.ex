defmodule LightningWeb.RunLive.RunViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}

  alias LightningWeb.RunLive.Components

  @impl true
  def render(assigns) do
    ~H"""
    <Components.run_details run={@run} />
    <Components.log_view log={@run.log || []} />
    """
  end

  @impl true
  def mount(_params, %{"run_id" => run_id}, socket) do
    run = Lightning.Invocation.get_run!(run_id)

    LightningWeb.Endpoint.subscribe("run:#{run.id}")
    {:ok, socket |> assign(run: run), layout: false}
  end

  @doc """
  Reload the run when any update messages arrive.
  """
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "update", payload: _payload},
        socket
      ) do
    {:noreply,
     socket |> assign(run: socket.assigns.run |> Lightning.Repo.reload!())}
  end
end
