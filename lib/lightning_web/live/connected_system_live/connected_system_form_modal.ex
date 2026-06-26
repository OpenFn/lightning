defmodule LightningWeb.ConnectedSystemLive.ConnectedSystemFormModal do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.ConnectedSystems
  alias Lightning.ConnectedSystems.ConnectedSystem
  alias Lightning.Helpers

  @impl true
  def update(assigns, socket) do
    connected_system = assigns.connected_system

    changeset =
      ConnectedSystem.form_changeset(
        connected_system,
        %{raw_name: connected_system.name}
      )

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:name, get_name(changeset))
     |> assign_new(:mode, fn -> :create end)}
  end

  defp get_name(changeset) do
    Ecto.Changeset.fetch_field!(changeset, :name)
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, socket |> push_navigate(to: socket.assigns.return_to)}
  end

  def handle_event("validate", %{"connected_system" => params}, socket) do
    changeset =
      socket.assigns.connected_system
      |> ConnectedSystem.form_changeset(params)
      |> Helpers.copy_error(:name, :raw_name)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, Ecto.Changeset.fetch_field!(changeset, :name))}
  end

  def handle_event("save", %{"connected_system" => params}, socket) do
    %{mode: mode, return_to: return_to} = socket.assigns
    params = derive_name(params)

    result =
      case mode do
        :create ->
          ConnectedSystems.create_connected_system(params)

        :update ->
          ConnectedSystems.update_connected_system(
            socket.assigns.connected_system,
            params
          )
      end

    case result do
      {:ok, _connected_system} ->
        {:noreply,
         socket
         |> put_flash(:info, "System #{mode}d successfully")
         |> push_navigate(to: return_to)}

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :changeset,
           Helpers.copy_error(changeset, :name, :raw_name)
         )}
    end
  end

  # The form field is `raw_name`; the canonical human `name` is the trimmed
  # value, and the slug is derived from it by the schema changeset.
  defp derive_name(%{"raw_name" => raw_name} = params),
    do: Map.put(params, "name", String.trim(raw_name))

  defp derive_name(params), do: params

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-1/2">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              {if @mode == :create, do: "Add System", else: "Edit System"}
            </span>
            <button
              id={"close-connected-system-#{@connected_system.id || "new"}-modal"}
              phx-click="close_modal"
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark-solid" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <.form
          :let={f}
          for={@changeset}
          id={"connected-system-form-#{@connected_system.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="container mx-auto space-y-4 bg-white">
            <.input
              type="text"
              field={f[:raw_name]}
              value={@name}
              label="Name"
              sublabel="A human-readable name, unique within this instance (e.g. Southwest Regional Health Tracker)."
              required="true"
            />
            <.input type="hidden" field={f[:name]} />
            <.input
              type="text"
              field={f[:type]}
              label="Type"
              sublabel="The adaptor or schema this system uses (e.g. dhis2, postgresql, @openfn/language-http)."
            />
            <.input
              type="textarea"
              field={f[:description]}
              label="Description"
            />
            <.input type="text" field={f[:docs_url]} label="Documentation URL" />
            <.input
              type="text"
              field={f[:contact]}
              label="Contact"
              sublabel="Who to contact to get access."
            />
            <.input
              type="textarea"
              field={f[:access_instructions]}
              label="Access instructions"
            />
          </div>
          <.modal_footer>
            <.button
              id={"save-connected-system-#{@connected_system.id || "new"}"}
              type="submit"
              theme="primary"
              disabled={!@changeset.valid?}
              phx-target={@myself}
            >
              Save
            </.button>
            <.button
              id={"cancel-connected-system-#{@connected_system.id || "new"}"}
              type="button"
              phx-click="close_modal"
              phx-target={@myself}
              theme="secondary"
            >
              Cancel
            </.button>
          </.modal_footer>
        </.form>
      </.modal>
    </div>
    """
  end
end
