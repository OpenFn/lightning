defmodule LightningWeb.ProjectLive.CollectionsComponent do
  @moduledoc false

  use LightningWeb, :live_component
  import PetalComponents.Table

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Helpers

  @impl true
  def mount(socket) do
    {:ok, assign(socket, action: nil, collection: nil, collections: [])}
  end

  @impl true
  def update(
        %{can_create_collection: _, collections: _, return_to: _, project: _} =
          assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def handle_event("toggle_action", %{"action" => "new"}, socket) do
    with :ok <- can_create_collection(socket) do
      changeset = Collection.form_changeset(%Collection{}, %{})

      {:noreply,
       assign(socket,
         changeset: changeset,
         collection: %Collection{},
         action: :new
       )}
    end
  end

  def handle_event(
        "toggle_action",
        %{"action" => "edit", "collection" => collection_name},
        socket
      ) do
    with :ok <- can_create_collection(socket) do
      {:ok, collection} = Collections.get_collection(collection_name)

      changeset =
        Collection.form_changeset(collection, %{raw_name: collection.name})

      {:noreply,
       assign(socket,
         changeset: changeset,
         collection: collection,
         action: :edit
       )}
    end
  end

  def handle_event(
        "toggle_action",
        %{"action" => "delete", "collection" => collection_name},
        socket
      ) do
    with :ok <- can_create_collection(socket) do
      {:ok, collection} = Collections.get_collection(collection_name)

      {:noreply, assign(socket, collection: collection, action: :delete)}
    end
  end

  def handle_event("reset_action", _, socket) do
    {:noreply, assign(socket, action: nil)}
  end

  def handle_event("delete_collection", %{"collection" => collection_id}, socket) do
    with :ok <- can_create_collection(socket) do
      case Collections.delete_collection(collection_id) do
        {:ok, _collection} ->
          {:noreply,
           socket
           |> put_flash(:info, "Collection deleted")
           |> push_navigate(to: socket.assigns.return_to)}

        {:error, _reason} ->
          {:noreply,
           socket
           |> put_flash(:error, "Couldn't delete collection!")
           |> push_navigate(to: socket.assigns.return_to)}
      end
    end
  end

  def handle_event("validate", %{"collection" => collection_params}, socket) do
    changeset =
      socket.assigns.collection
      |> Collection.form_changeset(collection_params)
      |> Helpers.copy_error(:name, :raw_name)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"collection" => params}, socket) do
    with :ok <- can_create_collection(socket) do
      {:noreply, save_collection(socket, socket.assigns.action, params)}
    end
  end

  defp save_collection(socket, :new, params) do
    params
    |> Map.put("project_id", socket.assigns.project.id)
    |> Collections.create_collection()
    |> case do
      {:ok, _collection} ->
        socket
        |> put_flash(:info, "Collection created")
        |> push_navigate(to: socket.assigns.return_to)

      {:error, :exceeds_limit, %{text: error_msg}} ->
        socket
        |> put_flash(:error, error_msg)
        |> push_navigate(to: socket.assigns.return_to)

      {:error, changeset} ->
        assign(
          socket,
          :changeset,
          Helpers.copy_error(changeset, :name, :raw_name)
        )
    end
  end

  defp save_collection(socket, :edit, params) do
    case Collections.update_collection(socket.assigns.collection, params) do
      {:ok, _collection} ->
        socket
        |> put_flash(:info, "Collection updated")
        |> push_navigate(to: socket.assigns.return_to)

      {:error, changeset} ->
        assign(
          socket,
          :changeset,
          Helpers.copy_error(changeset, :name, :raw_name)
        )
    end
  end

  defp can_create_collection(socket) do
    if socket.assigns.can_create_collection do
      :ok
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action")
       |> push_navigate(to: socket.assigns.return_to)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <div class="flex justify-between content-center pb-2">
        <div class="leading-loose">
          <h6 class="font-medium text-black">Project collections</h6>
          <small class="block text-xs text-gray-600">
            Manage collections for this project.
          </small>
          <LightningWeb.ProjectLive.Settings.permissions_message
            :if={!@can_create_collection}
            section="available collections."
          />
        </div>
        <div class="sm:block">
          <.button
            role="button"
            id="open-create-collection-modal-button"
            phx-click="toggle_action"
            phx-value-action="new"
            phx-target={@myself}
            disabled={!@can_create_collection}
          >
            Create collection
          </.button>
        </div>
      </div>

      <.form_modal_component
        :if={@action == :new}
        id="create-collection-modal"
        changeset={@changeset}
        myself={@myself}
        title="Create Collection"
      />
      <.form_modal_component
        :if={@action == :edit}
        id={"edit-collection-#{@collection.id}-modal"}
        changeset={@changeset}
        myself={@myself}
        title="Edit Collection"
      />
      <.collection_deletion_modal
        :if={@action == :delete}
        id={"delete-collection-#{@collection.id}-modal"}
        collection={@collection}
        myself={@myself}
      />

      <.table id="collections-table" rows={@collections}>
        <.tr>
          <.th>Name</.th>
          <.th>Used Storage (MB)</.th>
          <.th><span class="sr-only">Actions</span></.th>
        </.tr>

        <%= for collection <- @collections do %>
          <.tr id={"collection-row-#{collection.id}"}>
            <.td>
              {collection.name}
            </.td>
            <.td>
              {div(collection.byte_size_sum, 1_000_000)}
            </.td>
            <.td>
              <div class="text-right">
                <.button
                  id={"edit-collection-#{collection.id}-button"}
                  phx-click="toggle_action"
                  phx-value-action="edit"
                  phx-value-collection={collection.name}
                  phx-target={@myself}
                  theme="secondary"
                  disabled={!@can_create_collection}
                >
                  Edit
                </.button>

                <.button
                  id={"delete-collection-#{collection.id}-button"}
                  phx-click="toggle_action"
                  phx-value-action="delete"
                  phx-value-collection={collection.name}
                  phx-target={@myself}
                  theme="secondary"
                  disabled={!@can_create_collection}
                >
                  Delete
                </.button>
              </div>
            </.td>
          </.tr>
        <% end %>
      </.table>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :changeset, :map, required: true
  attr :myself, :any, required: true
  attr :title, :string, required: true

  defp form_modal_component(assigns) do
    ~H"""
    <.modal id={@id} show={true} width="xl:min-w-1/3 min-w-1/2 max-w-full">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            {@title}
          </span>
          <button
            id={"close-modal-#{@id}"}
            phx-click="reset_action"
            phx-target={@myself}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <.form
        :let={f}
        for={@changeset}
        phx-target={@myself}
        phx-change="validate"
        phx-submit="save"
      >
        <div class="container mx-auto px-6 space-y-6 bg-white">
          <div class="space-y-4">
            <.input type="text" field={f[:raw_name]} label="Name" required="true" />
            <.input type="hidden" field={f[:name]} />
            <small class="mt-2 block text-xs text-gray-600">
              <%= if to_string(f[:name].value) != "" do %>
                Your collection will be named <span class="font-mono border rounded-md p-1 bg-yellow-100 border-slate-300">
      <%= f[:name].value %></span>.
              <% end %>
            </small>
          </div>
        </div>
        <.modal_footer class="mt-6 mx-6">
          <div class="sm:flex sm:flex-row-reverse gap-3">
            <.button
              id={"submit-btn-#{@id}"}
              type="submit"
              disabled={!@changeset.valid?}
            >
              Save
            </.button>
            <.button
              id={"cancel-btn-#{@id}"}
              type="button"
              phx-click="reset_action"
              phx-target={@myself}
              theme="secondary"
            >
              Cancel
            </.button>
          </div>
        </.modal_footer>
      </.form>
    </.modal>
    """
  end

  attr :id, :string, required: true
  attr :collection, Collection, required: true
  attr :myself, :any, required: true

  defp collection_deletion_modal(assigns) do
    ~H"""
    <.modal id={@id} show={true} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete collection
          </span>

          <button
            phx-click="reset_action"
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
      <div class="px-6">
        <p class="text-sm text-gray-500">
          Are you sure you want to delete the collection
          <span class="font-medium">{@collection.name}</span>
          ?
          If you wish to proceed with this action, click on the delete button. To cancel click on the cancel button.<br /><br />
        </p>
      </div>
      <div class="flex flex-row-reverse gap-4 mx-6 mt-2">
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-click="delete_collection"
          phx-value-collection={@collection.id}
          phx-target={@myself}
          theme="danger"
          phx-disable-with="Deleting..."
        >
          Delete
        </.button>
        <.button
          type="button"
          phx-click="reset_action"
          phx-target={@myself}
          theme="secondary"
        >
          Cancel
        </.button>
      </div>
    </.modal>
    """
  end
end
