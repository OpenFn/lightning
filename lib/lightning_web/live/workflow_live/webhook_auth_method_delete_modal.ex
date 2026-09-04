defmodule LightningWeb.WorkflowLive.WebhookAuthMethodDeleteModal do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Repo
  alias Lightning.WebhookAuthMethods
  alias LightningWeb.Components.Common

  @impl true
  def update(
        %{
          webhook_auth_method: webhook_auth_method,
          current_user: _user,
          on_close: _on_close,
          return_to: _return_to
        } =
          assigns,
        socket
      ) do
    socket
    |> assign(:delete_confirmation_changeset, delete_confirmation_changeset())
    |> assign(assigns)
    |> assign(
      :webhook_auth_method,
      Repo.preload(webhook_auth_method, triggers: :workflow, channels: [])
    )
    |> ok()
  end

  @impl true
  def handle_event(
        "validate_deletion",
        %{"delete_confirmation" => params},
        socket
      ) do
    changeset =
      delete_confirmation_changeset(params)
      |> Map.put(:action, :validate)

    socket |> assign(:delete_confirmation_changeset, changeset) |> noreply()
  end

  def handle_event(
        "perform_deletion",
        %{"delete_confirmation" => params},
        socket
      ) do
    changeset =
      delete_confirmation_changeset(params)
      |> Map.put(:action, :validate)

    if changeset.valid? do
      case WebhookAuthMethods.schedule_for_deletion(
             socket.assigns.webhook_auth_method,
             actor: socket.assigns.current_user
           ) do
        {:ok, _} ->
          {:noreply,
           socket
           |> put_flash(
             :info,
             "Your Webhook Authentication method has been deleted."
           )
           |> push_patch(to: socket.assigns.return_to)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      {:noreply, socket |> assign(:delete_confirmation_changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.modal id={"#{@id}_modal"} on_close={@on_close} show={true}>
        <:title>
          <div class="flex justify-between">
            <span>
              Delete Authentication Method
            </span>
            <button
              phx-click={@on_close}
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
          for={@delete_confirmation_changeset}
          as={:delete_confirmation}
          phx-change="validate_deletion"
          phx-submit="perform_deletion"
          phx-target={@myself}
        >
          <div class="space-y-4">
            <p :if={
              @webhook_auth_method.triggers == [] and
                @webhook_auth_method.channels == []
            }>
              You are about to delete the webhook auth method
              "<span class="font-bold">{@webhook_auth_method.name}</span>" which is
              used by no workflows or channels.
            </p>
            <p :if={
              @webhook_auth_method.triggers != [] or
                @webhook_auth_method.channels != []
            }>
              You are about to delete the webhook auth method
              "<span class="font-bold">{@webhook_auth_method.name}</span>". This
              cannot be undone, and it will be removed from everything listed
              below.
            </p>

            <Common.alert
              :if={@webhook_auth_method.triggers != []}
              id={"#{@id}_linked_triggers"}
              type="warning"
              header={
                "#{count_label(@webhook_auth_method.triggers, "workflow trigger")} will stop requiring authentication"
              }
            >
              <:message>
                <ul class="list-disc pl-5 space-y-1">
                  <li :for={trigger <- @webhook_auth_method.triggers}>
                    <.link
                      navigate={
                        ~p"/projects/#{trigger.workflow.project_id}/w/#{trigger.workflow_id}?s=#{trigger.id}"
                      }
                      class="link"
                      target="_blank"
                    >
                      {trigger.workflow.name}
                    </.link>
                  </li>
                </ul>
              </:message>
            </Common.alert>

            <Common.alert
              :if={@webhook_auth_method.channels != []}
              id={"#{@id}_linked_channels"}
              type="danger"
              header={
                "#{count_label(@webhook_auth_method.channels, "channel")} will accept unauthenticated requests"
              }
            >
              <:message>
                <ul class="list-disc pl-5 space-y-1">
                  <li :for={
                    channel <-
                      Enum.sort_by(@webhook_auth_method.channels, & &1.name)
                  }>
                    <.link
                      navigate={
                        ~p"/projects/#{channel.project_id}/channels/#{channel.id}/edit"
                      }
                      class="link"
                      target="_blank"
                    >
                      {channel.name}
                    </.link>
                  </li>
                </ul>
                <p class="mt-2">
                  These channels stay enabled and keep forwarding requests to
                  their destination with the project credential attached. Add
                  another client auth method, or disable the channels, before
                  deleting this one.
                </p>
              </:message>
            </Common.alert>

            <.label for={:confirmation}>
              Type in 'DELETE' to confirm the deletion
            </.label>
            <.input type="text" field={f[:confirmation]} />
          </div>
          <.modal_footer class="mx-6 mt-6">
            <div class="sm:flex sm:flex-row-reverse gap-3">
              <.button
                type="submit"
                phx-disable-with="Deleting..."
                theme="danger"
                disabled={!@delete_confirmation_changeset.valid?}
              >
                Delete authentication method
              </.button>
              <.button type="button" phx-click={@on_close} theme="secondary">
                Cancel
              </.button>
            </div>
          </.modal_footer>
        </.form>
      </.modal>
    </div>
    """
  end

  defp count_label(items, noun) do
    case length(items) do
      1 -> "1 #{noun}"
      count -> "#{count} #{noun}s"
    end
  end

  defp delete_confirmation_changeset(params \\ %{}) do
    {%{confirmation: ""}, %{confirmation: :string}}
    |> Ecto.Changeset.cast(
      params,
      [:confirmation]
    )
    |> Ecto.Changeset.validate_required([:confirmation],
      message: "Please type DELETE to confirm"
    )
    |> Ecto.Changeset.validate_inclusion(:confirmation, ["DELETE"],
      message: "Please type DELETE to confirm"
    )
  end
end
