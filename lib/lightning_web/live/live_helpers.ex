defmodule LightningWeb.LiveHelpers do
  @moduledoc """
  General purpose LiveView helper functions
  """
  import Phoenix.LiveView
  import Phoenix.LiveView.Helpers

  alias Phoenix.LiveView.JS

  @doc """
  Renders a live component inside a modal.

  The rendered modal receives a `:return_to` option to properly update
  the URL when the modal is closed.

  ## Examples

      <.modal return_to={Routes.job_index_path(@socket, :index)}>
        <.live_component
          module={LightningWeb.JobLive.FormComponent}
          id={@job.id || :new}
          title={@page_title}
          action={@live_action}
          return_to={Routes.job_index_path(@socket, :index)}
          job: @job
        />
      </.modal>
  """
  def modal(assigns) do
    assigns = assign_new(assigns, :return_to, fn -> nil end)

    ~H"""
    <div id="modal" class="phx-modal fade-in" phx-remove={hide_modal()}>
      <div
        id="modal-content"
        class="phx-modal-content fade-in-scale"
        phx-click-away={JS.dispatch("click", to: "#close")}
        phx-window-keydown={JS.dispatch("click", to: "#close")}
        phx-key="escape"
      >
        <%= if @return_to do %>
          <%= live_patch("✖",
            to: @return_to,
            id: "close",
            class: "phx-modal-close",
            phx_click: hide_modal()
          ) %>
        <% else %>
          <a id="close" href="#" class="phx-modal-close" phx-click={hide_modal()}>
            ✖
          </a>
        <% end %>

        <%= render_slot(@inner_block) %>
      </div>
    </div>
    """
  end

  def live_info_block(assigns) do
    ~H"""
    <%= if info = live_flash(@flash, :info) do %>
      <div class="fixed h-16 top-3 right-3 z-10 ">
        <p
          class="bg-blue-200 border-blue-300 border opacity-75 py-4 px-5 rounded-md drop-shadow-lg"
          role="alert"
          phx-click="lv:clear-flash"
          phx-value-key="info"
        >
          <%= info %>
        </p>
      </div>
    <% end %>
    """
  end

  def live_error_block(assigns) do
    ~H"""
    <%= if error = live_flash(@flash, :error) do %>
      <div class="fixed h-16 top-3 right-3 z-10 ">
        <p
          class="bg-red-300 border-red-400 text-red-900 border opacity-75 py-4 px-5 rounded-md drop-shadow-lg"
          role="alert"
          phx-click="lv:clear-flash"
          phx-value-key="error"
        >
          <%= error %>
        </p>
      </div>
    <% end %>
    """
  end

  defp hide_modal(js \\ %JS{}) do
    js
    |> JS.hide(to: "#modal", transition: "fade-out")
    |> JS.hide(to: "#modal-content", transition: "fade-out-scale")
  end
end
