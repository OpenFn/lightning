defmodule Lightning.Storage do
  # defmodule ProjectArchive do
  #   use Waffle.Definition

  #   @versions [:archive]
  #   @extensions ~w(.zip)

  #   def validate({file, _}) do
  #     file_extension = file.file_name |> Path.extname() |> String.downcase()

  #     case Enum.member?(@extensions, file_extension) do
  #       true -> :ok
  #       false -> {:error, "file type is invalid"}
  #     end
  #   end

  #   # make a test file that exercises the ins and outs of the storage module
  #   # ProjectArchive.store and ProjectArchive.url
  #   def filename(_version, {_file, %{id: id}}) do
  #     id
  #   end

  #   def storage_dir(_, {_file, project_file}) do
  #     "archives/#{project_file.project_id}"
  #   end
  # end

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
      "archives/#{project_file.project_id}"
    end
  end
end
