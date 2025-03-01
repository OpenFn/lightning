defmodule Mix.Tasks.Compile.React do
  use Mix.Task.Compiler

  def run(args) do
    # Prevent LSP from triggering compilations
    # A better approach is to only re-compile when something's actually changed,
    # then LSP triggering this is a no-op
    # (LSP may run compilers to get diagnostics)
    unless "--return-errors" in args do
      app = Mix.Project.config()[:app]
      :ok = Application.ensure_loaded(app)

      entry_points =
        Application.spec(app, :modules)
        |> Enum.flat_map(fn module ->
          module.__info__(:attributes)
          |> Keyword.get_values(:external_resource)
          |> Enum.flat_map(fn files ->
            case files do
              files when is_list(files) ->
                files
                |> Enum.filter(fn file ->
                  String.starts_with?(
                    file,
                    Path.join(File.cwd!(), "assets/js/react")
                  )
                end)

              _ ->
                []
            end
          end)
        end)

      Esbuild.run(:react, entry_points)
    end

    :ok
  end
end
