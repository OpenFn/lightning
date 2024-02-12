defmodule LightningWeb.LiveHelpers do
  @moduledoc """
  General purpose LiveView helper functions
  """
  import Phoenix.Component

  alias LightningWeb.Components.Common
  alias LightningWeb.Components.Icon
  alias Phoenix.LiveView.JS

  def live_info_block(assigns) do
    assigns =
      assigns
      |> assign_new(:myself, fn -> nil end)
      |> assign_new(:id, fn -> Ecto.UUID.generate() end)

    ~H"""
    <%= if info = live_flash(@flash, :info) do %>
      <div
        class="fixed w-fit mx-auto flex justify-center bottom-3 right-0 left-0 z-[100]"
        id={@id}
      >
        <p
          class="bg-blue-200 border-blue-300 border opacity-75 py-4 px-5 rounded-md drop-shadow-lg"
          role="alert"
          phx-click="lv:clear-flash"
          phx-value-key="info"
          phx-target={@myself}
        >
          <%= info %>
        </p>
      </div>
    <% end %>
    """
  end

  def live_error_block(assigns) do
    assigns =
      assigns
      |> assign_new(:myself, fn -> nil end)
      |> assign_new(:id, fn -> Ecto.UUID.generate() end)

    ~H"""
    <%= if error = live_flash(@flash, :error) do %>
      <div
        class="fixed w-fit mx-auto flex justify-center bottom-3 right-0 left-0 z-[100]"
        id={@id}
      >
        <p
          class="bg-red-300 border-red-400 text-red-900 border opacity-75 py-4 px-5 rounded-md drop-shadow-lg"
          role="alert"
          phx-click="lv:clear-flash"
          phx-value-key="error"
          phx-target={@myself}
        >
          <%= error %>
        </p>
      </div>
    <% end %>
    """
  end

  def live_nav_block(assigns) do
    assigns =
      case live_flash(assigns[:flash], :nav) do
        :not_found ->
          assign(assigns,
            heading: "Not Found",
            blurb: "Sorry, we can't find anything here for you.",
            show_nav_error: true,
            show_back_button: true
          )

        :no_access ->
          assign(assigns,
            heading: "No Access",
            blurb: "Sorry, you don't have access to that.",
            show_nav_error: true,
            show_back_button: true
          )

        :no_access_no_back ->
          assign(assigns,
            heading: "No Access",
            blurb: "Sorry, you don't have access to that.",
            show_nav_error: true,
            show_back_button: false
          )

        _ ->
          assign(assigns, show_nav_error: false)
      end

    ~H"""
    <%= if @show_nav_error do %>
      <div class="flex items-start sm:items-center justify-center min-h-full p-4 text-center sm:p-0">
        <div class="relative bg-white rounded-lg text-left overflow-hidden shadow-md transform transition-all sm:my-8 sm:max-w-lg sm:w-full">
          <div class="bg-white px-4 pt-5 pb-4 sm:p-6 sm:pb-4">
            <div class="sm:flex sm:items-start">
              <div class="mx-auto flex-shrink-0 flex items-center justify-center h-12 w-12 rounded-full bg-red-100 sm:mx-0 sm:h-10 sm:w-10">
                <Heroicons.exclamation_triangle class="h-6 w-6 text-red-600" />
              </div>
              <div class="mt-3 text-center sm:mt-0 sm:ml-4 sm:text-left">
                <h3
                  class="text-lg leading-6 font-medium text-secondary-900"
                  id="modal-title"
                >
                  <%= @heading %>
                </h3>
                <div class="mt-2">
                  <p class="text-sm text-secondary-500">
                    <%= @blurb %>
                  </p>
                </div>
              </div>
            </div>
          </div>
          <div
            :if={@show_back_button}
            class="bg-secondary-50 px-4 py-3 sm:px-6 sm:flex"
          >
            <a href="javascript:history.back()">
              <Common.button>
                <div class="h-full">
                  <Icon.left class="h-4 w-4 inline-block" />
                  <span class="inline-block align-middle">Back</span>
                </div>
              </Common.button>
            </a>
          </div>
        </div>
      </div>
    <% else %>
      <%= render_slot(@inner_block) %>
    <% end %>
    """
  end

  @spec display_short_uuid(binary()) :: binary()
  def display_short_uuid(uuid_string) do
    uuid_string |> String.slice(0..7)
  end

  def upcase_first(nil), do: nil

  def upcase_first(<<first::utf8, rest::binary>>),
    do: String.upcase(<<first::utf8>>) <> rest

  def fade_in(opts \\ []) do
    Keyword.put(
      opts,
      :transition,
      {"ease-in duration-150", "opacity-0", "opacity-100"}
    )
    |> JS.show()
  end

  def fade_out(opts \\ []) do
    Keyword.put(
      opts,
      :transition,
      {"ease-out duration-300", "opacity-100", "opacity-0"}
    )
    |> JS.hide()
  end
end
