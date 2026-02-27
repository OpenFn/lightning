defmodule LightningWeb.ChannelLive.FormComponent do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Channels
  alias Lightning.Channels.Channel
  alias Lightning.Projects
  alias Lightning.WebhookAuthMethods

  import LightningWeb.ChannelLive.Helpers

  @impl true
  def update(
        %{channel: channel, project: project, on_close: _} = assigns,
        socket
      ) do
    changeset = Channel.changeset(channel, %{})

    wams = WebhookAuthMethods.list_for_project(project)
    pcs = Projects.list_project_credentials(project)

    current_source_ids =
      channel.channel_auth_methods
      |> Enum.filter(&(&1.role == :source))
      |> Enum.map(& &1.webhook_auth_method_id)

    current_sink_ids =
      channel.channel_auth_methods
      |> Enum.filter(&(&1.role == :sink))
      |> Enum.map(& &1.project_credential_id)

    source_selections =
      Map.new(wams, fn wam -> {wam.id, wam.id in current_source_ids} end)

    sink_selections =
      Map.new(pcs, fn pc -> {pc.id, pc.id in current_sink_ids} end)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       changeset: changeset,
       webhook_auth_methods: wams,
       project_credentials: pcs,
       source_selections: source_selections,
       sink_selections: sink_selections
     )}
  end

  @impl true
  def handle_event("validate", %{"channel" => params}, socket) do
    changeset =
      socket.assigns.channel
      |> Channel.changeset(params)
      |> Map.put(:action, :validate)

    source_selections =
      merge_selections(
        socket.assigns.source_selections,
        Map.get(params, "source_auth_methods", %{})
      )

    sink_selections =
      merge_selections(
        socket.assigns.sink_selections,
        Map.get(params, "sink_auth_methods", %{})
      )

    {:noreply,
     assign(socket,
       changeset: changeset,
       source_selections: source_selections,
       sink_selections: sink_selections
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
          class="flex items-center gap-1 mt-1 mb-4"
          phx-hook="Tooltip"
          aria-label="Copy URL"
          id={"copy-url-modal-#{@channel.id}"}
        >
          <span
            class="truncate font-mono text-xs text-gray-500 max-w-[20rem]"
            dir="rtl"
          >
            {channel_proxy_url(@channel.id)}
          </span>
          <button
            type="button"
            phx-hook="Copy"
            id={"copy-url-modal-btn-#{@channel.id}"}
            data-content={channel_proxy_url(@channel.id)}
            class="shrink-0 text-gray-400 hover:text-gray-600"
          >
            <.icon name="hero-clipboard-document" class="h-4 w-4" />
            <span class="sr-only">Copy URL</span>
          </button>
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
              field={f[:sink_url]}
              label="Sink URL"
              type="text"
              phx-debounce="300"
            />

            <.input field={f[:enabled]} label="Enabled" type="toggle" />

            <div>
              <div class="flex items-baseline gap-2 mb-2">
                <p class="text-sm/6 font-medium text-slate-800">
                  Source Authentication Methods
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
                  id={"source_auth_#{wam.id}"}
                  name={"#{f.name}[source_auth_methods][#{wam.id}]"}
                  type="checkbox"
                  value={Map.get(@source_selections, wam.id, false)}
                  label={wam.name}
                />
              </div>
            </div>

            <div>
              <div class="flex items-baseline gap-2 mb-2">
                <p class="text-sm/6 font-medium text-slate-800">
                  Sink Credentials
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
                  id={"sink_auth_#{pc.id}"}
                  name={"#{f.name}[sink_auth_methods][#{pc.id}]"}
                  type="checkbox"
                  value={Map.get(@sink_selections, pc.id, false)}
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
    params =
      Map.merge(params, %{
        "project_id" => socket.assigns.project.id,
        "channel_auth_methods" => build_auth_method_params(params, [])
      })

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
    params =
      Map.put(
        params,
        "channel_auth_methods",
        build_auth_method_params(
          params,
          socket.assigns.channel.channel_auth_methods
        )
      )

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

  defp build_auth_method_params(params, current_auth_methods) do
    build_auth_method_list(params, :source, current_auth_methods) ++
      build_auth_method_list(params, :sink, current_auth_methods)
  end

  defp build_auth_method_list(params, role, current_auth_methods) do
    id_field = auth_method_id_field(role)

    params
    |> Map.get(auth_method_param_key(role), %{})
    |> Enum.reduce([], fn {k, v}, acc ->
      existing_record =
        Enum.find(current_auth_methods, &(Map.get(&1, id_field) == k))

      case {existing_record, v} do
        {%{}, "true"} -> [%{id: existing_record.id} | acc]
        {nil, "true"} -> [%{id_field => k, role: to_string(role)} | acc]
        {%{}, _} -> [%{id: existing_record.id, delete: true} | acc]
        {nil, _} -> acc
      end
    end)
  end

  defp auth_method_id_field(:source), do: :webhook_auth_method_id
  defp auth_method_id_field(:sink), do: :project_credential_id

  defp auth_method_param_key(:source), do: "source_auth_methods"
  defp auth_method_param_key(:sink), do: "sink_auth_methods"
end
