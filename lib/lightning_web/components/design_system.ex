defmodule LightningWeb.Components.DesignSystem do
  @moduledoc """
  The LiveView side of the design-system page kit.

  A ported page is a React island under `assets/js/design-system/pages/`.
  The LiveView renders it with `design_system_page/1`, feeding it one
  `data-props` JSON attribute, and answers its events with a reply the kit
  understands: `{:reply, %{}, socket}` on success, `reply_error/2` on
  failure.
  """
  use Phoenix.Component
  use LightningWeb, :verified_routes

  alias LightningWeb.Components.Common
  alias LightningWeb.LayoutComponents

  attr :name, :string,
    required: true,
    doc: "the page module under assets/js/design-system/pages, e.g. TokensPage"

  attr :props, :map,
    required: true,
    doc: "camelCase keys, listed by hand; never a whole schema"

  attr :id, :string, default: nil, doc: "defaults to the name in kebab-case"
  attr :banner, :map, default: nil
  attr :current_user, Lightning.Accounts.User, default: nil

  def design_system_page(assigns) do
    assigns =
      assigns
      |> assign(:id, assigns.id || page_id(assigns.name))
      |> assign(:file, assigns.name <> ".js")

    ~H"""
    <div class="flex h-full w-full flex-col">
      <%!-- Loaded with the HTML, so the hook's import of the same URL finds the
      module evaluated and the page renders as soon as LiveView connects. --%>
      <script type="module" src={~p"/assets/js/design-system/pages/#{@file}"}>
      </script>
      <Common.dynamic_component
        :if={@banner}
        function={@banner.function}
        args={@banner.attrs}
      />
      <LayoutComponents.account_confirmation_banner current_user={@current_user} />
      <div
        id={@id}
        class="flex-auto"
        phx-hook="ReactComponent"
        phx-update="ignore"
        data-react-name={@name}
        data-react-file={~p"/assets/js/design-system/pages/#{@file}"}
        data-props={Jason.encode!(@props)}
      >
      </div>
    </div>
    """
  end

  defp page_id(name) do
    name |> Macro.underscore() |> String.replace("_", "-")
  end

  @doc """
  The reply the kit's `send` and `request` reject on. A changeset's errors
  are flattened to `fieldErrors`, keyed camelCase like
  `collaborators.0.email` or `rawName`, so the page can put each one under
  its field.
  """
  def reply_error(socket, message) when is_binary(message) do
    {:reply, %{error: message}, socket}
  end

  def reply_error(socket, %Ecto.Changeset{} = changeset) do
    {:reply,
     %{
       error: "Please fix the errors below.",
       fieldErrors: field_errors(changeset)
     }, socket}
  end

  defp field_errors(changeset) do
    changeset
    |> LightningWeb.CoreComponents.translate_errors()
    |> flatten([])
    |> Map.new()
  end

  # Props are camelCase (G45), so field errors are keyed the way the form is.
  defp camel_case(key) do
    case String.split(key, "_") do
      [head | rest] -> head <> Enum.map_join(rest, "", &String.capitalize/1)
      [] -> key
    end
  end

  defp flatten(%{} = map, path) do
    Enum.flat_map(map, fn {key, value} ->
      flatten(value, [to_string(key) | path])
    end)
  end

  defp flatten(messages, path) when is_list(messages) do
    if Enum.all?(messages, &is_binary/1) do
      [{path |> Enum.reverse() |> Enum.map_join(".", &camel_case/1), messages}]
    else
      messages
      |> Enum.with_index()
      |> Enum.flat_map(fn {value, i} ->
        flatten(value, [to_string(i) | path])
      end)
    end
  end
end
