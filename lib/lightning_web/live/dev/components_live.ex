defmodule LightningWeb.Dev.ComponentsLive do
  # Internal Development Page for viewing and working on components.
  # Access this page at /dev/components
  @moduledoc false
  use LightningWeb, {:live_view, layout: {LightningWeb.Layouts, :blank}}

  alias LightningWeb.Components.Viewers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(_unsigned_params, _uri, socket) do
    lines = log_lines()
    highlight_id = lines |> Enum.at(4) |> elem(0)

    {:noreply,
     socket
     |> assign(
       log_lines: lines,
       highlight_id: highlight_id
     )
     |> stream(
       :dataclip,
       dataclip()
       |> Enum.with_index(1)
       |> Enum.map(fn {line, index} -> %{id: index, line: line, index: index} end)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 flex flex-col gap-y-6">
      <h2 class="text-xl font-bold">Components</h2>
      <div class="overflow-hidden rounded-md bg-white shadow">
        <ul role="list" class="divide-y divide-gray-200">
          <li class="px-6 py-4">
            <h3 class="text-lg font-bold">Viewers</h3>
          </li>
          <.variation title="For a dataclip">
            <div class="max-h-[400px] inline-flex">
              <Viewers.dataclip_viewer
                id="dataclip-viewer"
                stream={@streams.dataclip}
                class=""
              />
            </div>
          </.variation>
          <.variation title="With data">
            <Viewers.log_viewer
              id="log-viewer-data"
              stream={@log_lines}
              highlight_id={@highlight_id}
            />
          </.variation>
          <.variation title="Empty">
            <Viewers.log_viewer id="log-viewer" stream={[]} />
          </.variation>
        </ul>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true
  slot :inner_block

  def variation(assigns) do
    ~H"""
    <li class="px-6 py-4 flex flex-col gap-y-4">
      <div class="text-right font-bold">
        <%= @title %>
      </div>
      <%= render_slot(@inner_block) %>
    </li>
    """
  end

  defp log_lines() do
    [
      %{source: "RUN", message: "Foo bar"},
      %{source: "RUN", message: "   Foo bar with indent"},
      %{source: "RUN", message: "Foo bar"},
      %{
        source: "RUN",
        message:
          "Foo bar #{Enum.map(1..5, fn _ -> " Foo bar #{Ecto.UUID.autogenerate()}" end)}"
      },
      %{source: "RUN", message: "I'm highlighted!"},
      %{source: "RUN", message: "Foo bar"},
      %{source: "LONG", message: "Foo bar"},
      %{
        source: "LONG",
        message:
          "Foo bar#{Enum.map(1..7, fn _ -> "  Foo bar with newlines and indent #{Ecto.UUID.autogenerate()}" end) |> Enum.intersperse("\n")}"
      },
      %{source: "LONG", message: "Foo bar"},
      %{source: "LONG", message: "Foo bar"},
      %{source: "RUN", message: "Foo bar"},
      %{source: "RUN", message: "Foo bar"},
      %{source: "RUN", message: "Foo bar"}
    ]
    |> Enum.map(fn line ->
      id = Ecto.UUID.autogenerate()
      {id, line |> Map.put(:run_id, id)}
    end)
  end

  defp dataclip() do
    File.read!("assets/package.json") |> String.split("\n")
  end
end
