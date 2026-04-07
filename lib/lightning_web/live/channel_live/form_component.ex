defmodule LightningWeb.ChannelLive.FormComponent do
  @moduledoc false
  use LightningWeb, :live_component

  import LightningWeb.ChannelLive.Helpers

  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Projects
  alias Lightning.WebhookAuthMethods

  @impl true
  def update(
        %{channel: channel, project: project, on_close: _} = assigns,
        socket
      ) do
    changeset = Channel.changeset(channel, %{})

    wams = WebhookAuthMethods.list_for_project(project)
    pcs = Projects.list_project_credentials(project)

    current_client_ids =
      channel.channel_auth_methods
      |> Enum.filter(&(&1.role == :client))
      |> Enum.map(& &1.webhook_auth_method_id)

    current_destination_ids =
      channel.channel_auth_methods
      |> Enum.filter(&(&1.role == :destination))
      |> Enum.map(& &1.project_credential_id)

    client_selections =
      Map.new(wams, fn wam -> {wam.id, wam.id in current_client_ids} end)

    destination_selections =
      Map.new(pcs, fn pc -> {pc.id, pc.id in current_destination_ids} end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       changeset: changeset,
       webhook_auth_methods: wams,
       project_credentials: pcs,
       client_selections: client_selections,
       destination_selections: destination_selections
     )}
  end

  @impl true
  def handle_event("validate", %{"channel" => params}, socket) do
    changeset =
      socket.assigns.channel
      |> Channel.changeset(params)
      |> Map.put(:action, :validate)

    client_selections =
      merge_selections(
        socket.assigns.client_selections,
        Map.get(params, "client_auth_methods", %{})
      )

    destination_selections =
      merge_selections(
        socket.assigns.destination_selections,
        Map.get(params, "destination_auth_methods", %{})
      )

    {:noreply,
     assign(socket,
       changeset: changeset,
       client_selections: client_selections,
       destination_selections: destination_selections
     )}
  end

  def handle_event("save", %{"channel" => params}, socket) do
    save_channel(socket, socket.assigns.action, params)
  end

  @impl true
  def render(assigns) do
    assigns =
      assign_new(assigns, :title, fn ->
        case assigns.action do
          :new -> "New Channel"
          :edit -> "Edit Channel"
        end
      end)

    ~H"""
    <div id={@id}>
      <.modal show id={"#{@id}-modal"} width="w-full max-w-lg" on_close={@on_close}>
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">{@title}</span>
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

        <div
          :if={@action == :edit}
          class="mb-4"
          phx-hook="Tooltip"
          aria-label="Copy proxy URL"
          id={"copy-url-modal-tooltip-#{@channel.id}"}
        >
          <label class="block text-sm font-medium leading-6 text-gray-900">
            Proxy URL
          </label>
          <.proxy_url_copy
            id={"copy-url-modal-#{@channel.id}"}
            channel_id={@channel.id}
            class="mt-1 min-w-0 hover:text-gray-600"
            text_class="text-gray-500"
          />
        </div>

        <.form
          :let={f}
          for={to_form(@changeset)}
          id={"channel-form-#{if @action == :edit, do: @channel.id, else: "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="space-y-6 bg-white">
            <.input field={f[:name]} label="Name" type="text" phx-debounce="300" />

            <.input
              field={f[:destination_url]}
              label="Destination URL"
              type="text"
              phx-debounce="300"
            />

            <.input field={f[:enabled]} label="Enabled" type="toggle" />

            <div>
              <div class="flex items-baseline gap-2 mb-2">
                <p class="text-sm/6 font-medium text-slate-800">
                  Client Credentials
                </p>
                <.link
                  navigate={~p"/projects/#{@project}/settings#webhook_security"}
                  class="text-xs link"
                >
                  Create a new one in project settings.
                </.link>
              </div>
              <div
                :if={@webhook_auth_methods != []}
                class="grid grid-cols-2 gap-x-4 gap-y-2"
              >
                <.input
                  :for={wam <- @webhook_auth_methods}
                  id={"client_auth_#{wam.id}"}
                  name={"#{f.name}[client_auth_methods][#{wam.id}]"}
                  type="checkbox"
                  value={Map.get(@client_selections, wam.id, false)}
                  label={wam.name}
                />
              </div>
            </div>

            <div>
              <div class="flex items-baseline gap-2 mb-2">
                <p class="text-sm/6 font-medium text-slate-800">
                  Destination Credential
                </p>
                <.link
                  navigate={~p"/projects/#{@project}/settings#credentials"}
                  class="text-xs link"
                >
                  Create a new one in project settings.
                </.link>
              </div>
              <div
                :if={@project_credentials != []}
                class="grid grid-cols-2 gap-x-4 gap-y-2"
              >
                <.input
                  :for={pc <- @project_credentials}
                  id={"destination_auth_#{pc.id}"}
                  name={"#{f.name}[destination_auth_methods][#{pc.id}]"}
                  type="checkbox"
                  value={Map.get(@destination_selections, pc.id, false)}
                  label={pc.credential.name}
                />
              </div>
            </div>
          </div>

          <.modal_footer>
            <.button type="submit" theme="primary" phx-target={@myself}>
              Save
            </.button>
            <.button theme="secondary" type="button" phx-click={@on_close}>
              Cancel
            </.button>
          </.modal_footer>
        </.form>
      </.modal>
    </div>
    """
  end

  defp save_channel(socket, :new, params) do
    built = %{
      "project_id" => socket.assigns.project.id,
      "client_auth_methods" => build_client_auth_params(params, [])
    }

    dest = build_destination_auth_param(params, [])

    built =
      if dest, do: Map.put(built, "destination_auth_method", dest), else: built

    params = Map.merge(params, built)

    case Channels.create_channel(params, actor: socket.assigns.current_user) do
      {:ok, _channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel created successfully.")
         |> push_patch(to: ~p"/projects/#{socket.assigns.project}/channels")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp save_channel(socket, :edit, params) do
    current = socket.assigns.channel.channel_auth_methods

    built = %{
      "client_auth_methods" => build_client_auth_params(params, current)
    }

    dest = build_destination_auth_param(params, current)

    built =
      if dest, do: Map.put(built, "destination_auth_method", dest), else: built

    params = Map.merge(params, built)

    case Channels.update_channel(
           socket.assigns.channel,
           params,
           actor: socket.assigns.current_user
         ) do
      {:ok, _channel} ->
        {:noreply,
         socket
         |> put_flash(:info, "Channel updated successfully.")
         |> push_patch(to: ~p"/projects/#{socket.assigns.project}/channels")}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp merge_selections(current, submitted) do
    Map.new(current, fn {k, _v} ->
      {k, Map.get(submitted, k, "false") == "true"}
    end)
  end

  defp build_client_auth_params(params, current_auth_methods) do
    params
    |> Map.get("client_auth_methods", %{})
    |> Enum.reduce([], fn {k, v}, acc ->
      existing =
        Enum.find(current_auth_methods, &(&1.webhook_auth_method_id == k))

      case {existing, v} do
        {%{}, "true"} -> [%{id: existing.id} | acc]
        {nil, "true"} -> [%{webhook_auth_method_id: k} | acc]
        {%{}, _} -> [%{id: existing.id, delete: true} | acc]
        {nil, _} -> acc
      end
    end)
  end

  defp build_destination_auth_param(params, current_auth_methods) do
    selected_id =
      params
      |> Map.get("destination_auth_methods", %{})
      |> Enum.find_value(fn {k, v} -> if v == "true", do: k end)

    existing =
      Enum.find(current_auth_methods, &(&1.role == :destination))

    cond do
      is_nil(selected_id) ->
        nil

      existing && existing.project_credential_id == selected_id ->
        %{id: existing.id}

      true ->
        %{project_credential_id: selected_id}
    end
  end
end
