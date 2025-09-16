defmodule LightningWeb.SandboxLive.FormComponent do
  use LightningWeb, :live_component

  alias Ecto.Changeset
  alias Lightning.Helpers
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias LightningWeb.Live.Helpers.ProjectTheme
  alias LightningWeb.SandboxLive.Components

  @type mode :: :new | :edit

  defp get_random_color do
    Components.color_palette_hex_colors() |> Enum.random()
  end

  defp generate_theme_preview(%Project{id: parent_id}, color)
       when is_binary(parent_id) and is_binary(color) and color != "" do
    temp_project = %Project{
      id: Ecto.UUID.generate(),
      color: String.trim(color),
      parent_id: parent_id
    }

    case ProjectTheme.inline_primary_scale(temp_project) do
      nil ->
        nil

      scale ->
        [scale, ProjectTheme.inline_sidebar_vars()]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
    end
  end

  defp generate_theme_preview(_parent, _color), do: nil

  defp should_preview_theme?(new_color, last_color) do
    is_binary(new_color) and new_color != last_color
  end

  defp send_theme_preview(parent, color) do
    theme = generate_theme_preview(parent, color)
    send(self(), {:preview_theme, theme})
  end

  defp reset_theme_preview do
    send(self(), {:preview_theme, nil})
  end

  defp return_path(socket) do
    socket.assigns.return_to ||
      ~p"/projects/#{socket.assigns.parent.id}/sandboxes"
  end

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw} = params) do
    Map.put(params, "name", Helpers.url_safe_name(raw))
  end

  defp coerce_raw_name_to_safe_name(params), do: params

  defp form_changeset(%Project{} = base, params) do
    params
    |> coerce_raw_name_to_safe_name()
    |> then(&Project.changeset(base, &1))
  end

  defp base_struct(%{sandbox: %Project{} = sandbox}), do: sandbox
  defp base_struct(_assigns), do: %Project{}

  defp initial_params(%{sandbox: %Project{} = sandbox}) do
    %{
      "name" => sandbox.name,
      "raw_name" => sandbox.name,
      "env" => sandbox.env,
      "color" => sandbox.color
    }
  end

  defp initial_params(%{mode: :new}) do
    %{"color" => get_random_color()}
  end

  defp initial_params(_assigns), do: %{}

  @impl true
  def update(%{mode: mode} = assigns, socket) when mode in [:new, :edit] do
    base = base_struct(assigns)

    changeset =
      base
      |> form_changeset(initial_params(assigns))
      |> Map.put(:action, :validate)

    initial_color = Changeset.get_field(changeset, :color)

    if should_preview_theme?(initial_color, nil) do
      send_theme_preview(assigns.parent, initial_color)
    end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:last_preview_color, initial_color)
     |> assign(:changeset, changeset)
     |> assign(:name, Changeset.get_field(changeset, :name))}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    reset_theme_preview()
    {:noreply, push_navigate(socket, to: return_path(socket))}
  end

  @impl true
  def handle_event(
        "validate",
        %{"project" => params},
        %{assigns: assigns} = socket
      ) do
    changeset =
      assigns
      |> base_struct()
      |> form_changeset(params)
      |> Map.put(:action, :validate)

    new_color = params["color"]
    last_color = socket.assigns[:last_preview_color]

    if should_preview_theme?(new_color, last_color) do
      send_theme_preview(assigns.parent, new_color)
    end

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, Changeset.get_field(changeset, :name))
     |> assign(:last_preview_color, new_color)}
  end

  @impl true
  def handle_event(
        "save",
        %{"project" => params},
        %{
          assigns: %{
            mode: mode,
            parent: parent,
            current_user: actor,
            return_to: return_to
          }
        } = socket
      )
      when mode in [:new, :edit] do
    attrs = %{
      name: params["name"],
      color: params["color"],
      env: params["env"]
    }

    result =
      case mode do
        :new ->
          Projects.provision_sandbox(parent, actor, attrs)

        :edit ->
          Projects.update_sandbox(parent, actor, socket.assigns.sandbox, attrs)
      end

    case result do
      {:ok, sandbox} ->
        flash_message =
          if mode == :new, do: "Sandbox created", else: "Sandbox updated"

        {:noreply,
         socket
         |> put_flash(:info, flash_message)
         |> push_navigate(to: return_to || ~p"/projects/#{sandbox.id}/w")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply,
         socket
         |> assign(:changeset, changeset)
         |> assign(:name, Changeset.get_field(changeset, :name))}
    end
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> assign_new(:title, fn ->
        case assigns.mode do
          :new -> "Create a new sandbox"
          :edit -> "Edit sandbox"
        end
      end)
      |> assign_new(:submit_label, fn ->
        case assigns.mode do
          :new -> "Create sandbox"
          :edit -> "Save changes"
        end
      end)

    ~H"""
    <div id={@id}>
      <.modal
        show
        id={"#{@id}-modal"}
        width="max-w-28rem"
        on_close={JS.push("close_modal", target: @myself)}
      >
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">{@title}</span>
            <button
              phx-click="close_modal"
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

        <:subtitle :if={@mode == :new}>
          <span class="text-sm text-slate-800">
            This sandbox will be created under the
            <span class="font-medium">{@parent.name}</span>
            {if Project.sandbox?(@parent), do: "sandbox", else: "project"}.
          </span>
        </:subtitle>

        <.form
          :let={f}
          for={@changeset}
          id={"sandbox-form-#{if @mode == :edit, do: @sandbox.id, else: "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="space-y-6 bg-white">
            <div class="space-y-2">
              <.input
                type="text"
                field={f[:raw_name]}
                label="Name"
                required
                autocomplete="off"
                placeholder="My Sandbox"
                phx-debounce="300"
              />
              <.input type="hidden" field={f[:name]} />

              <small class={[
                "block text-xs",
                if(to_string(f[:name].value) != "",
                  do: "text-gray-600",
                  else: "text-gray-400"
                )
              ]}>
                {case @mode do
                  :new -> "Your sandbox will be named"
                  :edit -> "The sandbox will be named"
                end}
                <%= if to_string(f[:name].value) != "" do %>
                  <span class="ml-1 rounded-md border border-slate-300 bg-yellow-100 p-1 font-mono text-xs">
                    <%= @name %>
                  </span>.
                <% else %>
                  <span class="ml-1 rounded-md border border-slate-200 bg-gray-50 p-1 font-mono text-xs">
                    my-sandbox
                  </span>.
                <% end %>
              </small>
            </div>

            <.input
              type="text"
              field={f[:env]}
              label="Environment"
              placeholder="staging"
              autocomplete="off"
            />

            <Components.color_palette id="sandbox-color-picker" field={f[:color]} />
          </div>

          <.modal_footer>
            <.button
              type="submit"
              theme="primary"
              disabled={@mode == :new && !@changeset.valid?}
              phx-target={@myself}
            >
              {@submit_label}
            </.button>
            <.button
              theme="secondary"
              type="button"
              phx-click="close_modal"
              phx-target={@myself}
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
