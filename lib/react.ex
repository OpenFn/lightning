defmodule React do
  @moduledoc """
  A way to use React with **Phoenix LiveView**.
  """
  use Phoenix.Component

  alias React.IOHelper

  # TODO: instead of statically using `assets/js/react`, we could have a
  # have a `__using__` macro that takes a path to the React components.
  # And then use that module in the component modules.
  #
  # defmodule LightningWeb.React do
  #   use React, path: "assets/js/react"
  # end
  #
  # defmodule MyComponent do
  #   use LightningWeb.React
  #   jsx "components/MyComponent.tsx"
  # end

  @doc """
  Returns a list of React components that are defined in the given app.
  """
  @spec get_entry_points(atom()) :: [String.t()]
  def get_entry_points(app) do
    Application.spec(app, :modules)
    |> Enum.flat_map(fn module ->
      module.__info__(:attributes)
      |> Keyword.get_values(:external_resource)
      |> List.flatten()
    end)
    |> Enum.filter(fn file -> String.ends_with?(file, ".tsx") end)
  end

  @doc """
  Associates a JSX file with a component.
  File paths are relative to the `assets/js/react` directory.
  Such files will become entrypoints for ESBuild, but common code is code-split
  by ESBuild into separate chunks.

  A custom Mix compiler will ensure these files are compiled.

  ## Example

      defmodule Button do
        use React.Component

        jsx "components/Button.tsx"
      end

  """
  defmacro jsx(relative_file) do
    # TODO: how to refer to the `assets` dir correctly, i.e. taking into account
    # a Plug.Static setting could change it?
    file =
      Path.dirname(__DIR__)
      |> Path.join(relative_file)

    if File.exists?(file) do
      name = file |> Path.rootname() |> Path.basename()

      asset =
        Path.join("/", relative_file)
        |> Path.rootname()
        |> Kernel.<>(".js")

      id = React.component_id(name)

      quote bind_quoted: [name: name, file: file, asset: asset, id: id] do
        # A custom Mix compiler collects all the files directly depended on this
        # way and creates entry points from them. This way we only build entry
        # points for actual entry points, and not every single React component.
        # It also code splits and chunks things nicely
        @external_resource file

        attr :"react-id", :string, default: nil
        attr :"react-portal-target", :string, default: nil

        def unquote(String.to_atom(name))(var!(assigns)) do
          # The script tag will be updated by LiveView and contain the data, as a JSON "DOM turd".
          # When it is updated, the `ReactComponent` client hook will re-parse
          # the data and re-render the React component.
          # The div will be used to actually mount and render the React Component in.

          # |> then(fn assigns ->
          #   case assigns do
          #     %{:children => _} ->
          #       raise "assigns should not have :children"

          #     %{:inner_block => children} ->
          #       assigns
          #       |> Map.drop(:inner_block)
          #       |> Map.put(:children, children)

          #     %{} ->
          #       assigns
          #   end
          # end

          var!(assigns) =
            var!(assigns)
            |> Map.merge(%{
              :__id__ => var!(assigns)[:id] || unquote(id),
              :__name__ => unquote(name),
              :__asset__ => unquote(asset),
              :__react_id__ => var!(assigns)[:"react-id"],
              :__react_portal_target__ => var!(assigns)[:"react-portal-target"]
            })
            |> Map.drop([:"react-id", :"react-portal-target"])
            |> React.Slots.render_slots()

          ~H"""
          <script
            id={@__id__}
            type="application/json"
            data-react-file={@__asset__}
            data-react-name={@__name__}
            data-react-id={@__react_id__}
            data-react-portal-target={@__react_portal_target__}
            phx-hook="ReactComponent"
          >
            <%= raw(React.json(assigns)) %>
          </script>
          <div
            id={"#{@__id__}-container"}
            data-react-container={@__id__}
            phx-update="ignore"
            style="display: contents"
          />
          """
        end
      end
    else
      message = """
      could not read template "#{relative_file}": no such file or directory. \
      Trying to read file "#{file}".
      """

      IOHelper.compile_error(message, __CALLER__.file, __CALLER__.line)
    end
  end

  @doc """
  Generates a unique ID for a React component.
  """
  @spec component_id(String.t()) :: String.t()
  def component_id(name) do
    # a small trick to avoid collisions of IDs but keep them consistent
    # across dead and live renders
    # id(name) is called only once during the whole LiveView lifecycle
    # because it's not using any assigns
    number = Process.get(:react_counter, 1)
    Process.put(:react_counter, number + 1)
    "#{name}-#{number}"
  end

  def json(data),
    do:
      Phoenix.json_library().encode!(
        Map.reject(data, fn {key, _val} ->
          String.starts_with?(to_string(key), "__")
        end),
        escape: :html_safe
      )
end
