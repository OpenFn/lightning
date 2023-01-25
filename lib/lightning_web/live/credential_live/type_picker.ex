defmodule LightningWeb.CredentialLive.TypePicker do
  use LightningWeb, :live_component

  alias LightningWeb.Components.Common

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mt-10 sm:mt-0">
      <div class="md:grid md:grid-cols-3 md:gap-6">
        <div class="md:col-span-1">
          <div class="px-4 sm:px-0">
            <p class="mt-1 text-sm text-gray-600">
              Decide which type credential you would like to create.
            </p>
          </div>
        </div>
        <div class="mt-5 md:col-span-2 md:mt-0">
          <div class="overflow-hidden shadow sm:rounded-md">
            <div class="space-y-6 bg-white px-4 py-5 sm:p-6">
              <fieldset>
                <legend class="contents text-base font-medium text-gray-900">
                  Types
                </legend>
                <p class="text-sm text-gray-500">
                  These are the different kinds of credentials that can be created.
                </p>
                <.form
                  :let={f}
                  id="credential-type-picker"
                  for={:type}
                  phx-target={@myself}
                  phx-change="type_changed"
                  phx-submit="confirm_type"
                >
                  <div class="mt-4 space-y-4">
                    <div
                      :for={{name, key} <- @type_options}
                      class="flex items-center"
                    >
                      <%= radio_button(f, :selected, key,
                        class:
                          "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500"
                      ) %>
                      <LightningWeb.Components.Form.label_field
                        form={f}
                        field={:selected}
                        for={"credential-type-picker_selected_#{key}"}
                        title={name}
                        class="ml-3 block text-sm font-medium text-gray-700"
                        value={key}
                      />
                    </div>
                  </div>
                </.form>
              </fieldset>
            </div>
            <div class="bg-gray-50 px-4 py-3 text-right sm:px-6">
              <Common.button
                disabled={!@selected}
                phx-click={@on_confirm}
                phx-target={@phx_target || @myself}
                value={@selected}
              >
                <div class="h-full">
                  <span class="inline-block align-middle">Continue</span>
                  <Heroicons.arrow_long_right class="h-4 w-4 inline-block" />
                </div>
              </Common.button>
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    schemas_options =
      Path.wildcard("#{schemas_path}/*.json")
      |> Enum.map(fn p ->
        name = p |> Path.basename() |> String.replace(".json", "")
        {name |> Phoenix.HTML.Form.humanize(), name}
      end)

    {:ok,
     socket
     |> assign(type_options: [{"Raw", "raw"} | schemas_options])}
  end

  @impl true
  def update(%{on_confirm: on_confirm} = assigns, socket) do
    {:ok,
     socket
     |> assign(%{
       on_confirm: on_confirm,
       phx_target: assigns[:phx_target] || socket.assigns.myself
     })
     |> assign_new(:selected, fn -> nil end)}
  end

  @impl true
  def handle_event("type_changed", %{"type" => %{"selected" => type}}, socket) do
    {:noreply, socket |> assign(selected: type)}
  end
end
