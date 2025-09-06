defmodule LightningWeb.SandboxLive.FormComponent do
  use LightningWeb, :live_component

  alias Ecto.Changeset
  alias Lightning.Helpers
  alias Lightning.Projects.Project

  @type mode :: :new | :edit

  defp coerce_raw_name_to_safe_name(%{"raw_name" => raw} = params) do
    Map.put(params, "name", Helpers.url_safe_name(raw))
  end

  defp coerce_raw_name_to_safe_name(params), do: params

  defp form_changeset(%Project{} = base, params) do
    params
    |> coerce_raw_name_to_safe_name()
    |> then(&Project.changeset(base, &1))
  end

  defp base_struct(%{sandbox: %Project{} = sb}), do: sb
  defp base_struct(_assigns), do: %Project{}

  defp initial_params(%{sandbox: %Project{} = sb}) do
    %{
      "name" => sb.name,
      "raw_name" => sb.name,
      "env" => sb.env,
      "color" => sb.color
    }
  end

  defp initial_params(_assigns), do: %{}

  @impl true
  def update(%{mode: mode} = assigns, socket) when mode in [:new, :edit] do
    base = base_struct(assigns)

    changeset =
      base
      |> form_changeset(initial_params(assigns))
      |> Map.put(:action, :validate)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:name, Changeset.get_field(changeset, :name))}
  end

  @impl true
  def handle_event("close_modal", _params, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
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

    {:noreply,
     socket
     |> assign(:changeset, changeset)
     |> assign(:name, Changeset.get_field(changeset, :name))}
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
          Lightning.Projects.Sandboxes.provision(parent, actor, attrs)

        :edit ->
          sb = socket.assigns.sandbox
          Lightning.Projects.Sandboxes.update(parent, actor, sb, attrs)
      end

    case result do
      {:ok, _sandbox} ->
        msg = if mode == :new, do: "Sandbox created", else: "Sandbox updated"

        {:noreply,
         socket
         |> put_flash(:info, msg)
         |> push_navigate(to: return_to)}

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
        if assigns.mode == :new, do: "Create a new sandbox", else: "Edit sandbox"
      end)
      |> assign_new(:submit_label, fn ->
        if assigns.mode == :new, do: "Create sandbox", else: "Save changes"
      end)

    ~H"""
    <div class="text-xs">
      <.modal show id={@id} width="xl:min-w-1/3 min-w-1/2 max-w-full">
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

        <.form
          :let={f}
          for={@changeset}
          id={"sandbox-form-#{if @mode == :edit, do: @sandbox.id, else: "new"}"}
          phx-target={@myself}
          phx-change="validate"
          phx-submit="save"
        >
          <div class="container mx-auto space-y-6 bg-white">
            <div class="space-y-2">
              <.input
                type="text"
                field={f[:raw_name]}
                label="Name"
                required
                autocomplete="off"
                placeholder="My Sandbox"
                phx-debounce="250"
              />
              <.input type="hidden" field={f[:name]} />

              <small class={[
                "block text-xs",
                (to_string(f[:name].value) != "" && "text-gray-600") ||
                  "text-gray-400"
              ]}>
                {if @mode == :new,
                  do: "Your sandbox will be named",
                  else: "The sandbox will be named"}
                <%= if to_string(f[:name].value) != "" do %>
                  <span class="ml-1 rounded-md border border-slate-300 bg-yellow-100 p-1 font-mono">
                    <%= @name %>
                  </span>.
                <% else %>
                  <span class="ml-1 rounded-md border border-slate-200 bg-gray-50 p-1 font-mono">
                    e.g. my-sandbox
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

            <% hex = LightningWeb.Utils.normalize_hex(f[:color].value || "#336699") %>
            <.input
              type="color"
              field={f[:color]}
              value={hex}
              label="Color"
              shape="rounded"
              wrapper_class="mt-2"
              swatch_class="ring-1 ring-offset-1"
              swatch_style={"--ring: #{hex}; box-shadow: 0 0 0 1px var(--ring) inset, 0 0 0 2px white inset; border-color: var(--ring);"}
            />
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
