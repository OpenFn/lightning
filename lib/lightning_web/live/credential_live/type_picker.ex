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
        <div class="grid grid-cols-2 md:grid-cols-4 sm:grid-cols-3 gap-4 overflow-auto max-h-99">
          <div
            :for={{name, key, logo} <- @type_options}
            class="flex items-center p-2"
          >
            <%= Phoenix.HTML.Form.radio_button(f, :selected, key,
              id: "credential-type-picker_selected_#{key}",
              class: "h-4 w-4 border-gray-300 text-indigo-600 focus:ring-indigo-500"
            ) %>
            <LightningWeb.Components.Form.label_field
              form={f}
              field={:selected}
              for={"credential-type-picker_selected_#{key}"}
              title={name}
              logo={logo}
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

    schemas_options =
      Path.wildcard("#{schemas_path}/*.json")
      |> Enum.map(fn p ->
        name = p |> Path.basename() |> String.replace(".json", "")
        {name |> Phoenix.HTML.Form.humanize(), name, nil}
      end)

    oauth_clients =
      Application.get_env(:lightning, :oauth_clients)

    type_options =
      schemas_options
      |> Enum.concat([{"Raw JSON", "raw", nil}])
      |> handle_oauth_item(
        {"GoogleSheets", "googlesheets",
         Routes.static_path(socket, "/images/oauth-2.png")},
        get_in(oauth_clients, [:google, :client_id])
      )
      |> handle_oauth_item(
        {
          "Salesforce",
          "salesforce_oauth",
          Routes.static_path(socket, "/images/oauth-2.png")
        },
        get_in(oauth_clients, [:salesforce, :client_id])
      )
      |> Enum.sort_by(& &1, :asc)

    {:ok, socket |> assign(type_options: type_options)}
  end

  defp handle_oauth_item(list, {_label, id, _image} = item, client_id) do
    if is_nil(client_id) || Enum.member?(list, item) do
      # Replace
      Enum.reject(list, fn {_first, second, _third} -> second == id end)
    else
      Enum.map(list, fn
        {_old_label, old_id, _old_image} when old_id == id -> item
        old_item -> old_item
      end)
      |> append_if_missing(item)
    end
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
  def handle_event(
        "type_changed",
        %{"type" => %{"selected" => type}},
        socket
      ) do
    send(self(), {:credential_type_changed, type})
    {:noreply, socket}
  end

  def handle_event("type_changed", %{"_target" => ["type", "selected"]}, socket) do
    {:noreply, socket}
  end
end
