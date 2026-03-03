defmodule LightningWeb.CollectionLive.CollectionCreationModal do
  use LightningWeb, :live_component

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Extensions.Message
  alias Lightning.Helpers
  alias Lightning.Projects

  @impl true
  def update(assigns, socket) do
    collection = assigns.collection

    changeset =
      if collection.name do
        Collection.form_changeset(collection, %{raw_name: collection.name})
      else
        Collection.form_changeset(collection, %{})
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:name, get_collection_name(changeset))
     |> assign(:projects_options, list_project_options())
     |> assign_new(:mode, fn -> :create end)}
  end

  defp list_project_options do
    Projects.list_projects() |> Enum.map(&{&1.name, &1.id})
  end

  defp get_collection_name(changeset) do
    Ecto.Changeset.fetch_field!(changeset, :name)
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, socket |> push_navigate(to: socket.assigns.return_to)}
  end

  def handle_event("validate", %{"collection" => collection_params}, socket) do
    changeset =
      socket.assigns.collection
      |> Collection.form_changeset(collection_params)
      |> Helpers.copy_error(:name, :raw_name)
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, Ecto.Changeset.fetch_field!(changeset, :name))}
  end

  def handle_event("save", %{"collection" => collection_params}, socket) do
    %{mode: mode, return_to: return_to} = socket.assigns
    collection_params = Helpers.derive_name_param(collection_params)

    result =
      case mode do
        :create ->
          Collections.create_collection(collection_params)

        :update ->
          Collections.update_collection(
            socket.assigns.collection,
            collection_params
          )
      end

    case result do
      {:ok, _collection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Collection #{mode}d successfully")
         |> push_navigate(to: return_to)}

      {:error, :exceeds_limit, %Message{text: error_msg}} ->
        {:noreply,
         socket
         |> put_flash(:error, error_msg)
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

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-1/2">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              {if @mode == :create,
                do: "Create Collection",
                else: "Edit Collection"}
            </span>
            <button
              id={"close-collection-#{@collection.id || "new"}-creation-modal"}
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
          id={"collection-form-#{@collection.id || "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="container mx-auto space-y-6 bg-white">
            <div class="space-y-4">
              <.input
                type="text"
                field={f[:raw_name]}
                value={@name}
                label="Name"
                sublabel="Collection names must be unique across all projects within this instance. They are used in URLs and as titles, so duplicates are not allowed."
                required="true"
              />
              <.input type="hidden" field={f[:name]} />
              <small class="mt-2 block text-xs text-gray-600">
                <.name_badge name={@name} field={f[:name]}>
                  This collection will be named
                </.name_badge>
              </small>
            </div>
            <div class="space-y-4">
              <.input
                type="select"
                field={f[:project_id]}
                label="Project"
                options={@projects_options}
                required="true"
              />
            </div>
          </div>
          <.modal_footer>
            <.button
              id={"save-collection-#{@collection.id || "new"}"}
              type="submit"
              theme="primary"
              disabled={!@changeset.valid?}
              phx-target={@myself}
            >
              Save
            </.button>
            <.button
              id={"cancel-collection-creation-#{@collection.id || "new"}"}
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
