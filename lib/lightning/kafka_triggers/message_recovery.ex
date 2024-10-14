defmodule Lightning.KafkaTriggers.MessageRecovery do
  alias Lightning.KafkaTriggers.Pipeline

  def recover_messages(base_dir_path) do
    error_count =
      find_recoverable_files(base_dir_path)
      |> Enum.reduce(0, fn file_path, error_counter ->
        %{"data" => data, "metadata" => metadata} =
          deserialise_contents(file_path)

        metadata = convert_keys_to_atoms(metadata)

        message = build_broadway_message(data, metadata)

        %{status: status} = 
          Pipeline.handle_message(
            nil,
            message,
            %{trigger_id: extract_trigger_id(file_path)}
          )

        if status == :ok do
          File.rename!(file_path, "#{file_path}.recovered")
          error_counter
        else
          error_counter + 1
        end
      end)

    if error_count == 0, do: :ok, else: {:error, error_count}
  end

  defp find_recoverable_files(base_dir_path) do
    base_dir_path
    |> File.ls!()
    |> Enum.map(
      &Path.join(base_dir_path, &1)
    )
    |> Enum.filter(&File.dir?/1)
    |> Enum.flat_map(fn dir_path ->
      File.ls!(dir_path)
      |> Enum.map(&Path.join(dir_path, &1))
    end)
    |> Enum.filter(fn file_path -> Path.extname(file_path) == ".json" end)
  end

  defp deserialise_contents(file_path) do
    File.read!(file_path) |> Jason.decode!()
  end

  defp convert_keys_to_atoms(map) do
    map
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      Map.put(acc, String.to_atom(key), value)
    end)
  end

  def build_broadway_message(data, metadata) do
    %Broadway.Message{acknowledger: %{}, data: data, metadata: metadata}
  end

  def extract_trigger_id(file_path) do
    Path.basename(file_path)
    |> String.split("_")
    |> List.first()
    |> String.to_atom()
  end
end
