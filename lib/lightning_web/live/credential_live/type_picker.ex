defmodule LightningWeb.CredentialLive.TypePicker do
  use LightningWeb, :live_component

  @impl true
  def render(assigns) do
    ~H"""
    <div class="container mx-auto px-4">
      <.form
        :let={f}
        id="credential-type-picker"
        for={%{"selected" => @selected}}
        as={:type}
        phx-target={@myself}
        phx-change="type_changed"
      >
        <div class="grid grid-cols-2 md:grid-cols-4 gap-4 overflow-auto max-h-99">
          <div :for={{name, key} <- @type_options} class="flex items-center pt-2">
            <%= Phoenix.HTML.Form.radio_button(f, :selected, key,
              class: "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500"
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
    </div>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, schemas_path} = Application.fetch_env(:lightning, :schemas_path)

    enable_google_credential =
      Application.get_env(:lightning, LightningWeb, [])
      |> Keyword.get(:enable_google_credential)

    schemas_options =
      Path.wildcard("#{schemas_path}/*.json")
      |> Enum.map(fn p ->
        name = p |> Path.basename() |> String.replace(".json", "")
        {name |> Phoenix.HTML.Form.humanize(), name}
      end)

    type_options =
      schemas_options
      |> append_if_missing({"Raw JSON", "raw"})
      |> append_if_missing({"Googlesheets", "googlesheets"})
      |> Enum.sort_by(& &1, :asc)
      |> Enum.filter(fn {_, key} ->
        case key do
          "googlesheets" ->
            enable_google_credential

          _ ->
            true
        end
      end)

    {:ok, socket |> assign(type_options: type_options)}
  end

  defp append_if_missing(list, item) do
    if Enum.member?(list, item), do: list, else: list ++ [item]
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
    send(self(), {:credential_type_changed, type})
    {:noreply, socket}
  end
end
