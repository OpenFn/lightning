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

    client_selections =
      Map.new(wams, fn wam -> {wam.id, wam.id in current_client_ids} end)

    destination_credential_id =
      channel.channel_auth_methods
      |> Enum.find(&(&1.role == :destination))
      |> case do
        nil -> nil
        cam -> cam.project_credential_id
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       changeset: changeset,
       webhook_auth_methods: wams,
       project_credentials: pcs,
       client_selections: client_selections,
       destination_credential_id: destination_credential_id
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

    destination_credential_id =
      case Map.get(params, "destination_credential_id", "") do
        "" -> nil
        id -> id
      end

    {:noreply,
     assign(socket,
       changeset: changeset,
       client_selections: client_selections,
       destination_credential_id: destination_credential_id
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

            <div>
              <.input
                field={f[:destination_url]}
                label="Destination URL"
                type="text"
                placeholder="https://"
                phx-debounce="300"
              />
              <p class="mt-1 text-xs text-gray-500">
                The service OpenFn will forward requests to
              </p>
            </div>

            <div>
              <div class="flex items-baseline gap-2 mb-2">
                <p class="text-sm/6 font-medium text-slate-800">
                  Destination Credential
                </p>
                <.link
                  href={~p"/projects/#{@project}/settings#credentials"}
                  target="_blank"
                  class="text-xs link"
                >
                  Add New
                </.link>
              </div>
              <p class="mb-2 text-xs text-gray-500">
                How OpenFn authenticates with the destination service
              </p>
              <select
                name={"#{f.name}[destination_credential_id]"}
                class="block w-full rounded-md border-gray-300 shadow-sm focus:border-primary-300 focus:ring focus:ring-primary-200 focus:ring-opacity-50 sm:text-sm"
              >
                <option value="">None</option>
                <option
                  :for={pc <- @project_credentials}
                  value={pc.id}
                  selected={@destination_credential_id == pc.id}
                >
                  {pc.credential.name}
                </option>
              </select>
            </div>

            <.input field={f[:enabled]} label="Enabled" type="toggle" />

            <div>
              <div class="flex items-baseline gap-2 mb-2">
                <p class="text-sm/6 font-medium text-slate-800">
                  Client Credentials
                </p>
                <.link
                  href={~p"/projects/#{@project}/settings#webhook_security"}
                  target="_blank"
                  class="text-xs link"
                >
                  Add New
                </.link>
              </div>
              <p class="mb-2 text-xs text-gray-500">
                Credentials that you can use to access this channel
              </p>
              <p
                :if={@webhook_auth_methods == []}
                class="italic text-xs text-gray-400"
              >
                No webhook auth methods available.
              </p>
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
    params =
      build_auth_params(params, [], %{"project_id" => socket.assigns.project.id})

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
    params = build_auth_params(params, current)

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

  defp build_auth_params(params, current_auth_methods, extra \\ %{}) do
    built =
      Map.merge(extra, %{
        "client_auth_methods" =>
          build_client_auth_params(params, current_auth_methods)
      })

    built =
      case build_destination_auth_param(params, current_auth_methods) do
        nil -> built
        :clear -> Map.put(built, "destination_auth_method", nil)
        dest -> Map.put(built, "destination_auth_method", dest)
      end

    Map.merge(params, built)
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
      case Map.get(params, "destination_credential_id", "") do
        "" -> nil
        id -> id
      end

    existing = Enum.find(current_auth_methods, &(&1.role == :destination))

    case {existing, selected_id} do
      {nil, nil} -> nil
      {%{}, nil} -> :clear
      {%{id: id, project_credential_id: pc_id}, pc_id} -> %{id: id}
      {_, _} -> %{project_credential_id: selected_id}
    end
  end
end
