defmodule LightningWeb.CredentialLive.RawBody do
  use LightningWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <div class="space-y-6 bg-white px-4 py-5 sm:p-6">
        <div :for={above <- @above} class={above[:class]}>
          <%= render_slot(above) %>
        </div>

        <div class="hidden sm:block" aria-hidden="true">
          <div class="border-t border-secondary-200"></div>
        </div>
        <fieldset>
          <legend class="contents text-base font-medium text-gray-900">
            Details
          </legend>
          <p class="text-sm text-gray-500">
            Configuration for this credential.
          </p>

          <div class="text-right">
            <span class="text-sm text-secondary-700">
              Required
            </span>
          </div>
          <div>
            <%= error_tag(@form, :body, class: "block w-full rounded-md") %>
            <%= textarea(@form, :body,
              class: "rounded-md w-full font-mono bg-slate-800 text-slate-100"
            ) %>
          </div>
        </fieldset>

        <div :for={below <- @below} class={below[:class]}>
          <%= render_slot(below) %>
        </div>
      </div>

      <div class="bg-gray-50 px-4 py-3 sm:px-6">
        <div class="flex flex-rows">
          <div :for={button <- @button} class={button[:class]}>
            <%= render_slot(button, @valid?) %>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @valid_assigns [
    :below,
    :above,
    :button
  ]

  @impl true
  def update(%{form: form} = assigns, socket) do
    changeset = form.source

    {:ok,
     socket
     |> assign(
       form: form,
       input: [],
       valid?: changeset.valid?
     )
     |> assign(assigns |> filter_assigns(@valid_assigns))}
  end

  defp filter_assigns(assigns, keys) do
    assigns |> Map.filter(fn {k, _} -> k in keys end)
  end
end
