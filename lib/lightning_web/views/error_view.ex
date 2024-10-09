defmodule LightningWeb.ErrorView do
  # This module needs to be changed to use Layouts
  use LightningWeb, :view

  use Phoenix.Component

  def render("404.html", assigns) do
    ~H"""
    <.logo_bar conn={@conn} />
    <div class="min-h-[25em] flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-6 p-12 rounded-md shadow-md border bg-white">
        <div>
          <h2 class="text-center text-4xl tracking-tight font-bold text-gray-900">
            Not Found
          </h2>
          <p class="mt-2 text-center text-sm text-gray-600">
            Sorry that page doesn't appear to exist.
          </p>
        </div>
      </div>
    </div>
    """
  end

  def render("401.html", assigns) do
    ~H"""
    <.logo_bar conn={@conn} />
    <div class="min-h-[25em] flex items-center justify-center py-12 px-4 sm:px-6 lg:px-8">
      <div class="max-w-md w-full space-y-6 p-12 rounded-md shadow-md border bg-white">
        <div>
          <h2 class="text-center text-4xl tracking-tight font-bold text-gray-900">
            Authorization Error
          </h2>
          <div class="mt-4 p-4 text-xs font-mono text-gray-600 border rounded-md bg-gray-200 grid grid-cols-2 gap-2">
            <%= for {k,v} <- @error do %>
              <div class="text-right font-bold"><%= k %></div>
              <div><%= v %></div>
            <% end %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp logo_bar(assigns) do
    ~H"""
    <nav class="bg-secondary-800">
      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div class="flex items-center justify-between h-16">
          <div class="flex items-center">
            <div class="flex-shrink-0">
              <img
                class="h-8 w-8"
                src={Routes.static_path(@conn, "/images/square-logo.png")}
                alt="OpenFn"
              />
            </div>
          </div>
        </div>
      </div>
    </nav>
    """
  end

  # By default, Phoenix returns the status message from
  # the template name. For example, "404.html" becomes
  # "Not Found".
  def template_not_found(template, _assigns) do
    if String.match?(template, ~r/.json$/) do
      %{
        "error" => Phoenix.Controller.status_message_from_template(template)
      }
    else
      Phoenix.Controller.status_message_from_template(template)
    end
  end
end
