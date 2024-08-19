defmodule Lightning.Storage do
  defmodule ProjectFileDefinition do
    use Waffle.Definition
    use Waffle.Ecto.Definition

    @versions [:original]
    @extensions ~w(.zip)

    def validate({file, _}) do
      file_extension = file.file_name |> Path.extname() |> String.downcase()

      case Enum.member?(@extensions, file_extension) do
        true -> :ok
        false -> {:error, "file type is invalid"}
      end
    end

    def filename(_version, {_file, %{id: id}}) do
      id
    end

    def storage_dir(_, {_file, project_file}) do
      "exports/#{project_file.project_id}"
    end
  end

  defmodule GCSTokenFetcher do
    @behaviour Waffle.Storage.Google.Token.Fetcher

    @impl true
    def get_token(scope) when is_binary(scope) do
      Goth.fetch!(Lightning.Goth).token
    end
  end
end
