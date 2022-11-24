defmodule LightningWeb.RunLive.Show do
  @moduledoc """
  Show page for individual runs.
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation.Run
  alias Phoenix.LiveView.JS

  import Ecto.Query
  import LightningWeb.RunLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :runs, page_title: "Run", section: "log")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :show, %{"id" => id}) do
    run =
      from(r in Run, where: r.id == ^id, preload: :output_dataclip)
      |> Lightning.Repo.one()

    socket |> assign(run: run, log: run.log || [])
  end

  @impl true
  def handle_event("change_section", %{"section" => section}, socket) do
    {:noreply, socket |> assign(section: section)}
  end

  def switch_section(section) do
    JS.hide(to: "[id$=_section]:not([id=#{section}_section])")
    |> JS.show(
      to: "##{section}_section",
      transition: {"ease-out duration-300", "opacity-0", "opacity-100"},
      time: 125
    )
    |> JS.set_attribute({"data-active", "false"},
      to: "[data-section]:not([data-section=#{section}])"
    )
    |> JS.set_attribute({"data-active", "true"}, to: "[data-section=#{section}]")
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layout.page_content>
      <:header>
        <Layout.header socket={@socket} title={@page_title} />
      </:header>
      <Layout.centered>
        <.run_details run={@run} />
        <.toggle_bar class="mt-4 items-end" phx-mounted={switch_section(@section)}>
          <.toggle_item
            active={@section == "outout"}
            data-section="outout"
            phx-click={switch_section("outout")}
          >
            Output
          </.toggle_item>
          <.toggle_item
            active={@section == "log"}
            data-section="log"
            phx-click={switch_section("log")}
          >
            Log
          </.toggle_item>
        </.toggle_bar>

        <div id="log_section" style="display: none;">
          <.log_view log={@log} />
        </div>
        <div id="outout_section" style="display: none;">
          <.dataclip_view dataclip={@run.output_dataclip} />
        </div>
      </Layout.centered>
    </Layout.page_content>
    """
  end

  slot :inner_block, required: true
  attr :class, :string, default: "items-end"
  attr :rest, :global

  def toggle_bar(assigns) do
    ~H"""
    <div class={"flex flex-col #{@class}"} {@rest}>
      <div class="flex rounded-lg p-1 bg-gray-200 font-semibold">
        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  attr :active, :boolean, default: false
  slot :inner_block, required: true
  attr :rest, :global

  def toggle_item(assigns) do
    ~H"""
    <div
      data-active={@active}
      class="group text-sm shadow-sm text-gray-700
                     data-[active=true]:bg-white data-[active=true]:text-indigo-500
                     px-4 py-2 rounded-md align-middle flex items-center cursor-pointer"
      {@rest}
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end
end
