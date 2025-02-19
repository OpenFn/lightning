defmodule React do
  @moduledoc """
  A way to use React with **Phoenix LiveView**.
  """

  alias React.IOHelper

  # TODO: Figure out how to load the transpiled JSX file,
  # both eagerly and lazily

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
      |> Path.join("assets/js/react")
      |> Path.join(relative_file)

    if File.exists?(file) do
      name = file |> Path.rootname() |> Path.basename()

      asset =
        "/assets/js/react"
        |> Path.join(relative_file)
        |> Path.rootname()
        |> Kernel.<>(".js")

      quote bind_quoted: [name: name, file: file, asset: asset] do
        # A custom Mix compiler collects all the files directly depended on this
        # way and creates entry points from them. This way we only build entry
        # points for actual entry points, and not every single React component.
        # It also code splits and chunks things nicely
        @external_resource file

        # TODO: global attributes?
        # attr :rest, :global

        def unquote(String.to_atom(name))(var!(assigns)) do
          _ = var!(assigns)

          # The script tag will be updated by LiveView and contain the data, as a JSON "DOM turd".
          # When it is updated, the `ReactComponent` client hook will re-parse
          # the data and re-render the React component.
          # The div will be used to actually mount and render the React Component in.

          var!(assigns) =
            var!(assigns)
            |> Map.put(
              :props,
              Map.drop(var!(assigns), [:socket, :__changed__])
            )
            |> Map.put(:asset, unquote(asset))
            |> Map.put(:name, unquote(name))
            |> Map.put(:id, id(unquote(name)))

          ~H"""
          <script
            id={"#{@id}"}
            type="application/json"
            data-react-file={"#{@asset}"}
            data-react-name={"#{@name}"}
            phx-hook="ReactComponent"
          >
            <%= json(@props) %>
          </script>
          <div id={"#{@id}-container"} phx-update="ignore" data-react-container={"#{@id}"} />
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

  def json(data), do: Jason.encode!(data, escape: :html_safe)

  def id(name) do
    # a small trick to avoid collisions of IDs but keep them consistent across dead and live render
    # id(name) is called only once during the whole LiveView lifecycle because it's not using any assigns
    # TODO: could these collide if there are multiple LiveViews mounted in the DOM with the same component?
    number = Process.get(:react_counter, 1)
    Process.put(:react_counter, number + 1)
    "#{name}-#{number}"
  end
end
