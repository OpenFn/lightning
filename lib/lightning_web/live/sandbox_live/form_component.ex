defmodule LightningWeb.SandboxLive.FormComponent do
  use LightningWeb, :live_component

  alias Ecto.Changeset
  alias Lightning.Helpers
  alias Lightning.Projects
  alias Lightning.Projects.Project
  alias Lightning.Projects.ProjectLimiter
  alias LightningWeb.Live.Helpers.ProjectTheme
  alias LightningWeb.SandboxLive.Components

  @type mode :: :new | :edit

  @impl true
  def update(%{mode: mode} = assigns, socket) when mode in [:new, :edit] do
    base = base_struct(assigns)
    parent_id = get_parent_id(assigns)

    changeset =
      base
      |> form_changeset(initial_params(assigns), parent_id)
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
    parent_id = get_parent_id(assigns)

    changeset =
      assigns
      |> base_struct()
      |> form_changeset(params, parent_id)
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
            mode: :new,
            parent: parent,
            current_user: actor,
            return_to: return_to
          }
        } = socket
      ) do
    parent_users = Projects.get_project_users!(parent.id)

    collaborators =
      parent_users
      |> Enum.reject(fn pu -> pu.user_id == actor.id end)
      |> Enum.map(fn pu ->
        role = if pu.role == :owner, do: :admin, else: pu.role
        %{user_id: pu.user_id, role: role}
      end)

    attrs =
      params
      |> build_sandbox_attrs()
      |> Map.put(:env, "dev")
      |> Map.put(:collaborators, collaborators)

    with :ok <- ProjectLimiter.limit_new_sandbox(parent.id),
         {:ok, sandbox} <- Projects.provision_sandbox(parent, actor, attrs) do
      socket
      |> put_flash(:info, "Sandbox created")
      |> push_navigate(to: return_to || ~p"/projects/#{sandbox.id}/w")
      |> noreply()
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        socket
        |> assign(:changeset, changeset)
        |> assign(:name, Changeset.get_field(changeset, :name))
        |> noreply()

      {:error, _reason, %{text: text}} ->
        socket
        |> put_flash(:error, text)
        |> push_navigate(to: return_to || ~p"/projects/#{parent.id}/sandboxes")
        |> noreply()
    end
  end

  @impl true
  def handle_event(
        "save",
        %{"project" => params},
        %{
          assigns: %{
            mode: :edit,
            sandbox: sandbox,
            current_user: actor,
            return_to: return_to
          }
        } = socket
      ) do
    attrs = build_sandbox_attrs(params)

    case Projects.update_sandbox(sandbox, actor, attrs) do
      {:ok, sandbox} ->
        {:noreply,
         socket
         |> put_flash(:info, "Sandbox updated")
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
        width="w-full max-w-lg"
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

              <%= if f[:raw_name].errors == [] do %>
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
                    <span class={[
                      "ml-1 rounded-md border border-slate-300",
                      "bg-yellow-100 p-1 font-mono text-xs"
                    ]}><%= @name %></span>.
                  <% else %>
                    <span class={[
                      "ml-1 rounded-md border border-slate-200",
                      "bg-gray-50 p-1 font-mono text-xs"
                    ]}>my-sandbox</span>.
                  <% end %>
                </small>
              <% end %>
            </div>

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

  defp base_struct(%{sandbox: %Project{} = sandbox}), do: sandbox
  defp base_struct(_assigns), do: %Project{}

  defp get_parent_id(%{parent: %Project{id: id}}), do: id

  defp initial_params(%{sandbox: %Project{} = sandbox}) do
    %{
      "name" => sandbox.name,
      "raw_name" => sandbox.name,
      "color" => sandbox.color
    }
  end

  defp initial_params(%{mode: :new}) do
    %{"color" => get_random_color()}
  end

  defp form_changeset(%Project{} = base, params, parent_id) do
    params
    |> coerce_raw_name_to_safe_name()
    |> then(&Project.changeset(base, &1))
    |> validate_unique_sandbox_name(parent_id)
  end

  defp validate_unique_sandbox_name(changeset, parent_id) do
    name = Changeset.get_field(changeset, :name)
    id = Changeset.get_field(changeset, :id)

    if parent_id && name do
      if Projects.sandbox_name_exists?(parent_id, name, id) do
        Changeset.add_error(
          changeset,
          :raw_name,
          "Sandbox name already exists"
        )
      else
        changeset
      end
    else
      changeset
    end
  end

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw} = params) do
    Map.put(params, "name", Helpers.url_safe_name(raw))
  end

  defp coerce_raw_name_to_safe_name(params), do: params

  defp build_sandbox_attrs(params) do
    %{
      name: params["name"],
      color: params["color"]
    }
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

  defp get_random_color do
    Components.color_palette_hex_colors() |> Enum.random()
  end

  defp return_path(socket) do
    socket.assigns.return_to ||
      ~p"/projects/#{socket.assigns.parent.id}/sandboxes"
  end
end
