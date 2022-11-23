defmodule LightningWeb.RunLive.RunViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}

  @impl true
  def render(assigns) do
    ~H"""
    <LightningWeb.RunLive.Components.run_details run={@run} />
    <LightningWeb.RunLive.Components.log_view log={@run.log || []} />
    """
  end

  @impl true
  def mount(params, %{"run_id" => run_id}, socket) do
    IO.inspect(socket, label: "socket")
    IO.inspect(params, label: "params")
    run = Lightning.Invocation.get_run!(run_id)

    LightningWeb.Endpoint.subscribe("run:#{run.id}")
    {:ok, socket |> assign(run: run), layout: false}
  end

  @doc """
  Reload the run when any update messages arrive.
  """
  @impl true
  def handle_info(
        %Phoenix.Socket.Broadcast{event: "update", payload: _payload} = msg,
        socket
      ) do
    IO.inspect(msg)

    {:noreply,
     socket |> assign(run: socket.assigns.run |> Lightning.Repo.reload!())}
  end
end
