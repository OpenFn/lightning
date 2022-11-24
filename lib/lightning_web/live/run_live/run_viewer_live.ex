defmodule LightningWeb.RunLive.RunViewerLive do
  use LightningWeb, {:live_view, container: {:div, []}}

  import LightningWeb.RunLive.Components
  import Ecto.Query, only: [from: 2]

  @impl true
  def render(assigns) do
    ~H"""
    <.run_details run={@run} />
    <.toggle_bar class="mt-4 items-end" phx-mounted={show_section("log")}>
      <.toggle_item data-section="output" phx-click={switch_section("output")}>
        Output
      </.toggle_item>
      <.toggle_item
        data-section="log"
        phx-click={switch_section("log")}
        active="true"
      >
        Log
      </.toggle_item>
    </.toggle_bar>

    <div id="log_section" style="display: none;" class="@container">
      <%= if @run.log do %>
        <.log_view log={@run.log} />
      <% else %>
        <.no_log_message />
      <% end %>
    </div>
    <div id="output_section" style="display: none;" class="@container">
      <.dataclip_view dataclip={@run.output_dataclip} />
    </div>
    """
  end

  @impl true
  def mount(_params, %{"run_id" => run_id}, socket) do
    run = get_run_with_output(run_id)

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

  defp get_run_with_output(id) do
    from(r in Lightning.Invocation.Run,
      where: r.id == ^id,
      preload: :output_dataclip
    )
    |> Lightning.Repo.one()
  end
end
