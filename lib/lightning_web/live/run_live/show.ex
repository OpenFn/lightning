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
     |> assign(active_menu_item: :runs, page_title: "Run")}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  def apply_action(socket, :show, %{"id" => id}) do
    run =
      from(r in Run, where: r.id == ^id, preload: :output_dataclip)
      |> Lightning.Repo.one()

    socket |> assign(run: run, log: run.log)
  end

  def switch_section(section) do
    JS.hide(to: "[id$=_section]:not([id=#{section}_section])")
    |> JS.set_attribute({"data-active", "false"},
      to: "[data-section]:not([data-section=#{section}])"
    )
    |> show_section(section)
  end

  def show_section(js \\ %JS{}, section) do
    js
    |> JS.show(
      to: "##{section}_section",
      transition: {"ease-out duration-300", "opacity-0", "opacity-100"},
      time: 200
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
          <%= if @log do %>
            <.log_view log={@log} />
          <% else %>
            <.no_log_message />
          <% end %>
        </div>
        <div id="output_section" style="display: none;" class="@container">
          <.dataclip_view dataclip={@run.output_dataclip} />
        </div>
      </Layout.centered>
    </Layout.page_content>
    """
  end
end
