defmodule LightningWeb.CoreComponents do
  @moduledoc false

  use Phoenix.Component

  # TODO: Remove `Phoenix.HTML` and `error_tag` once we are in
  # a better position to conform the more recent Phoenix conventions.
  # use Phoenix.HTML

  alias Phoenix.LiveView.JS
  alias LightningWeb.Router.Helpers, as: Routes

  import LightningWeb.Components.NewInputs

  slot :actions

  def auth_footer_link(assigns) do
    ~H"""
    <div class="mt-10">
      <div
        :for={action <- @actions}
        class="flex items-center justify-between text-sm"
      >
        <%= render_slot(action) %>
      </div>
    </div>
    """
  end

  attr :button, :string

  def auth_submit(assigns) do
    ~H"""
    <div>
      <button
        type="submit"
        class="flex justify-center w-full px-4 py-4 text-sm font-medium text-white bg-indigo-600 border border-transparent rounded-md shadow-sm hover:bg-indigo-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-indigo-500"
      >
        <%= @button %>
      </button>
    </div>
    """
  end

  attr :conn, :map
  attr :heading, :string
  attr :flash, :map, default: %{}
  slot :inner_block, doc: "Inner content"

  def auth_wrapper(assigns) do
    ~H"""
    <div class="flex flex-col justify-center min-h-screen py-12 bg-secondary-800 sm:px-6 lg:px-8">
      <div class="sm:mx-auto sm:w-full sm:max-w-md">
        <img
          class="w-20 h-20 mx-auto"
          src={Routes.static_path(@conn, "/images/square-logo.png")}
          alt="Workflow"
        />
      </div>
      <div class="mt-8 sm:mx-auto sm:w-full sm:max-w-2xl">
        <div class="px-4 py-8 mx-4 bg-white rounded-lg shadow sm:px-10">
          <h2 class="mt-8 mb-12 text-3xl font-extrabold text-center">
            <%= @heading %>
          </h2>
          <.flash_message kind={:error} flash={@flash} />
          <.flash_message kind={:info} flash={@flash} />
          <%= render_slot(@inner_block) %>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders flash notices.

  ## Examples

      <.flash_message kind={:info} flash={@flash} />
      <.flash_message kind={:info} phx-mounted={show("#flash")}>Welcome Back!</.flash>
  """
  attr :id, :string, default: "flash", doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"

  attr :kind, :atom,
    values: [:info, :error],
    doc: "used for styling and flash lookup"

  slot :inner_block,
    doc: "the optional inner block that renders the flash message"

  def flash_message(assigns) do
    ~H"""
    <div
      :if={message = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
    >
      <div
        class={[
          "flex items-center justify-between max-w-3xl mb-8 rounded",
          @kind == :error && "bg-red-500",
          @kind == :info && "bg-green-500"
        ]}
        role="alert"
      >
        <div class="flex items-center">
          <svg
            :if={@kind == :error}
            class="flex-shrink-0 w-4 h-4 ml-4 mr-2 fill-white"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
          >
            <path d="M2.93 17.07A10 10 0 1 1 17.07 2.93 10 10 0 0 1 2.93 17.07zm1.41-1.41A8 8 0 1 0 15.66 4.34 8 8 0 0 0 4.34 15.66zm9.9-8.49L11.41 10l2.83 2.83-1.41 1.41L10 11.41l-2.83 2.83-1.41-1.41L8.59 10 5.76 7.17l1.41-1.41L10 8.59l2.83-2.83 1.41 1.41z" />
          </svg>
          <svg
            :if={@kind == :info}
            class="flex-shrink-0 w-4 h-4 ml-4 mr-2 fill-white"
            xmlns="http://www.w3.org/2000/svg"
            viewBox="0 0 20 20"
          >
            <polygon points="0 11 2 9 7 14 18 3 20 5 7 18" />
          </svg>
          <div class="py-4 text-sm font-medium text-white"><%= message %></div>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Generates tag for inlined form input errors.
  """

  attr :field, Phoenix.HTML.FormField,
    doc:
      "a form field struct retrieved from the form, for example: @form[:email]"

  def old_error(%{field: field} = assigns) do
    assigns =
      assigns |> assign(:errors, Enum.map(field.errors, &translate_error(&1)))

    ~H"""
    <.error :for={msg <- @errors}><%= msg %></.error>
    """
  end

  def show_modal(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-out duration-300", "opacity-0",
         "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      transition:
        {"transition-all transform ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.focus_first(to: "##{id}-content")
  end

  def hide_modal(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}-bg",
      transition:
        {"transition-all transform ease-in duration-200", "opacity-100",
         "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      time: 200,
      transition:
        {"transition-all transform ease-in duration-200",
         "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.pop_focus()
  end

  def show_dropdown(js \\ %JS{}, id) when is_binary(id) do
    js
    |> JS.show(
      to: "##{id}",
      transition:
        {"transition ease-out duration-100", "transform opacity-0 scale-95",
         "transform opacity-100 scale-100"}
    )
  end

  def hide_dropdown(js \\ %JS{}, id) do
    js
    |> JS.hide(
      to: "##{id}",
      transition:
        {"transition ease-in duration-75", "transform opacity-100 scale-100",
         "transform opacity-0 scale-95"}
    )
  end
end
