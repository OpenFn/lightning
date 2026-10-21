defmodule LightningWeb.CollectionLive.Index do
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :ensure_admin}

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Extensions.Message
  alias Lightning.Helpers
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.Projects
  alias Lightning.Repo

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Collections",
       active_menu_item: :collections
     )
     |> load(), layout: {LightningWeb.Layouts, :settings}}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # The page sorts in the browser; the list arrives by name.
  defp load(socket) do
    assign(socket,
      collections: Collections.list_collections(),
      project_options: Enum.map(Projects.list_projects(), &[&1.name, &1.id])
    )
  end

  # The create and edit dialogs are the page's own; each save is one event,
  # and the server derives the URL-safe name and checks the project again.
  @impl true
  def handle_event("create_collection", params, socket) do
    with :ok <- authorize(socket),
         {:ok, attrs} <- collection_attrs(socket, params) do
      attrs
      |> Collections.create_collection()
      |> saved(socket, "created")
    end
  end

  def handle_event("update_collection", %{"id" => id} = params, socket) do
    with :ok <- authorize(socket),
         {:ok, collection} <- fetch_collection(socket, id),
         {:ok, attrs} <- collection_attrs(socket, params) do
      collection
      |> Collections.update_collection(attrs)
      |> saved(socket, "updated")
    end
  end

  def handle_event("delete_collection", %{"collection" => id}, socket) do
    with :ok <- authorize(socket),
         {:ok, collection} <- fetch_collection(socket, id) do
      case Collections.delete_collection(collection.id) do
        {:ok, _collection} ->
          {:reply, %{},
           socket |> put_flash(:info, "Collection deleted") |> load()}

        {:error, reason} ->
          Logger.error("Error during collection deletion: #{inspect(reason)}")
          reply_error(socket, "Couldn't delete collection!")
      end
    end
  end

  # The mount gate is :ensure_admin; every event checks the same policy again.
  defp authorize(socket) do
    if Permissions.can?(
         Users,
         :access_admin_space,
         socket.assigns.current_user,
         {}
       ),
       do: :ok,
       else:
         reply_error(socket, "You are not authorized to perform this action.")
  end

  defp fetch_collection(socket, id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Collection{} = collection <- Repo.get(Collection, uuid) do
      {:ok, collection}
    else
      _ -> reply_error(socket, "Collection not found")
    end
  end

  # The page's values as the changeset's params: the name derived from what
  # was typed, as the old form did, and a project that exists.
  defp collection_attrs(socket, params) do
    project_id = params["projectId"]

    with {:ok, _uuid} <- Ecto.UUID.cast(to_string(project_id)),
         %{} <- Projects.get_project(project_id) do
      attrs =
        %{"raw_name" => params["rawName"], "project_id" => project_id}
        |> Helpers.derive_name_param()

      {:ok, attrs}
    else
      _ ->
        {:reply,
         %{
           error: "Please fix the errors below.",
           fieldErrors: %{"projectId" => ["Choose a project"]}
         }, socket}
    end
  end

  defp saved({:ok, _collection}, socket, verb) do
    {:reply, %{},
     socket |> put_flash(:info, "Collection #{verb} successfully") |> load()}
  end

  defp saved({:error, :exceeds_limit, %Message{text: text}}, socket, _verb),
    do: reply_error(socket, text)

  defp saved({:error, %Ecto.Changeset{} = changeset}, socket, _verb) do
    # The form shows the name's error on its Name field only (D29).
    changeset = Helpers.copy_error(changeset, :name, :raw_name)

    reply_error(socket, %{
      changeset
      | errors: Keyword.delete(changeset.errors, :name)
    })
  end

  # The shape the design system's AdminCollectionRow type expects.
  defp collections_json(collections) do
    Enum.map(collections, fn collection ->
      %{
        id: collection.id,
        name: collection.name,
        projectId: collection.project_id,
        projectName: collection.project.name,
        byteSizeSum: collection.byte_size_sum
      }
    end)
  end
end
