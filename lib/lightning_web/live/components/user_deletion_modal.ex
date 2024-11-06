defmodule LightningWeb.Components.UserDeletionModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       delete_now?: !is_nil(user.scheduled_deletion),
       has_activity_in_projects?: Accounts.has_activity_in_projects?(user),
       scheduled_deletion_changeset: Accounts.change_scheduled_deletion(user)
     )
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "validate",
        %{"user" => user_params},
        socket
      ) do
    changeset =
      socket.assigns.user
      |> Accounts.change_scheduled_deletion(user_params)
      |> Map.put(:action, :validate_scheduled_deletion)

    {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
  end

  @impl true
  def handle_event("delete", %{"user" => user_params}, socket) do
    cond do
      not socket.assigns.delete_now? ->
        case Accounts.schedule_user_deletion(
               socket.assigns.user,
               user_params["scheduled_deletion_email"]
             ) do
          {:ok, %User{}} ->
            {:noreply,
             socket
             |> put_flash(:info, "User scheduled for deletion")
             |> logout_after_deletion()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
        end

      socket.assigns.has_activity_in_projects? ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete user that has activities in other projects"
         )
         |> push_navigate(to: ~p"/settings/users")}

      true ->
        Accounts.purge_user(socket.assigns.user.id)

        {:noreply,
         socket
         |> put_flash(:info, "User deleted")
         |> push_navigate(to: ~p"/settings/users")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
  end

  defp logout_after_deletion(%{assigns: %{logout: true}} = socket),
    do: push_navigate(socket, to: Routes.user_session_path(socket, :delete))

  defp logout_after_deletion(%{assigns: %{logout: false}} = socket),
    do: push_navigate(socket, to: socket.assigns.return_to)

  @impl true
  def render(%{delete_now?: true, has_activity_in_projects?: true} = assigns) do
    ~H"""
    <.modal id={"user-#{@id}"} width="max-w-md" show={true}>
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete user
          </span>

          <button
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
      <div class="px-6">
        <p class="text-sm text-gray-500">
          This user cannot be deleted until their auditable activities have also been purged.
          <br /><br />Audit trails are removed on a project-basis and may be controlled by the project owner or a superuser.
        </p>
      </div>
      <div class="flex-grow bg-gray-100 h-0.5 my-[16px]"></div>
      <div class="flex flex-row-reverse gap-4 mx-6">
        <button
          type="button"
          phx-click="close_modal"
          phx-target={@myself}
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end

  def render(assigns) do
    ~H"""
    <.modal id={"user-#{@id}"} show={true} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete user
          </span>

          <button
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
        for={@scheduled_deletion_changeset}
        phx-change="validate"
        phx-submit="delete"
        phx-target={@myself}
        id="scheduled_deletion_form"
      >
        <div class="px-6">
          <p class="">
            This user's account and credential data will be deleted. Please make sure none of these credentials are used in production workflows.
          </p>
          <p :if={@has_activity_in_projects?} class="mt-2">
            *Note that this user still has activity related to active projects. We may not be able to delete them entirely from the app until those projects are deleted.
          </p>

          <div class="grid grid-cols-12 gap-12">
            <div class="col-span-8">
              <.input
                type="text"
                field={f[:scheduled_deletion_email]}
                label="User email"
              />
            </div>
          </div>
          <.input type="hidden" field={f[:id]} />
        </div>
        <div class="flex-grow bg-gray-100 h-0.5 my-[16px]"></div>
        <div class="flex flex-row-reverse gap-4 mx-6">
          <.button
            id={"user-#{@id}_confirm_button"}
            type="submit"
            color_class="bg-red-600 hover:bg-red-700 text-white"
            phx-disable-with="Deleting..."
          >
            Delete account
          </.button>
          <button
            type="button"
            phx-click="close_modal"
            phx-target={@myself}
            class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </.form>
    </.modal>
    """
  end
end
