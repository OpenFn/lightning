defmodule LightningWeb.CollectionLive.CollectionCreationModal do
  alias Lightning.Helpers
  use LightningWeb, :live_component

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Projects

  @impl true
  def update(assigns, socket) do
    changeset = Collection.changeset(assigns.collection, %{})

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
      |> Collection.changeset(
        collection_params
        |> coerce_raw_name_to_safe_name
      )
      |> Map.put(:action, :validate)

    {:noreply,
     socket
     |> assign(
       :changeset,
       Lightning.Helpers.copy_error(changeset, :name, :raw_name)
     )
     |> assign(:name, Ecto.Changeset.fetch_field!(changeset, :name))}
  end

  def handle_event("save", %{"collection" => collection_params}, socket) do
    %{mode: mode, return_to: return_to} = socket.assigns

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

      {:error, changeset} ->
        {:noreply,
         assign(
           socket,
           :changeset,
           Lightning.Helpers.copy_error(changeset, :name, :raw_name)
         )}
    end
  end

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw_name} = params) do
    new_name = Helpers.url_safe_name(raw_name)

    params |> Map.put("name", new_name)
  end

  defp coerce_raw_name_to_safe_name(%{} = params) do
    params
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              <%= if @mode == :create,
                do: "Create Collection",
                else: "Edit Collection" %>
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
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
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
          <div class="container mx-auto px-6 space-y-6 bg-white">
            <div class="space-y-4">
              <.input
                type="text"
                field={f[:raw_name]}
                value={@name}
                label="Name"
                required="true"
              />
              <.input type="hidden" field={f[:name]} />
              <small class="mt-2 block text-xs text-gray-600">
                <%= if to_string(f[:name].value) != "" do %>
                  Your collection will be named <span class="font-mono border rounded-md p-1 bg-yellow-100 border-slate-300">
      <%= @name %></span>.
                <% end %>
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
          <.modal_footer class="mt-6 mx-6">
            <div class="sm:flex sm:flex-row-reverse">
              <button
                id={"save-collection-#{@collection.id || "new"}"}
                type="submit"
                disabled={!@changeset.valid?}
                phx-target={@myself}
                class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
              >
                Save
              </button>
              <button
                id={"cancel-collection-creation-#{@collection.id || "new"}"}
                type="button"
                phx-click="close_modal"
                phx-target={@myself}
                class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
              >
                Cancel
              </button>
            </div>
          </.modal_footer>
        </.form>
      </.modal>
    </div>
    """
  end
end
