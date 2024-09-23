defmodule Lightning.KafkaTriggers do
  @moduledoc """
  Contains the logic to manage kafka trigger and their associated pipelines.
  """
  import Ecto.Query

  alias Ecto.Changeset
  alias Lightning.Repo
  alias Lightning.Workflows.Trigger

  def start_triggers do
    if supervisor = GenServer.whereis(:kafka_pipeline_supervisor) do
      find_enabled_triggers()
      |> Enum.each(fn trigger ->
        child_spec = generate_pipeline_child_spec(trigger)
        Supervisor.start_child(supervisor, child_spec)
      end)
    end

    :ok
  end

  def find_enabled_triggers do
    query =
      from t in Trigger,
        where: t.type == :kafka,
        where: t.enabled == true

    query |> Repo.all()
  end

  @doc """
  Selects the appropriate offset reset policy for a given trigger based on the
  presence of partition-specific timestamps.
  """
  def determine_offset_reset_policy(trigger) do
    %Trigger{kafka_configuration: kafka_configuration} = trigger

    case kafka_configuration do
      config = %{partition_timestamps: ts} when map_size(ts) == 0 ->
        initial_policy(config)

      %{partition_timestamps: ts} ->
        earliest_timestamp(ts)
    end
  end

  # Converts the initial_offset_reset_policy configuration value to a format
  # suitable for use by a `Pipeline` process.
  defp initial_policy(%{initial_offset_reset_policy: initial_policy}) do
    cond do
      initial_policy in ["earliest", "latest"] ->
        initial_policy |> String.to_atom()

      String.match?(initial_policy, ~r/^\d+$/) ->
        {timestamp, _remainder} = Integer.parse(initial_policy)
        {:timestamp, timestamp}

      true ->
        :latest
    end
  end

  defp earliest_timestamp(timestamps) do
    timestamp = timestamps |> Map.values() |> Enum.sort() |> hd()

    {:timestamp, timestamp}
  end

  @doc """
  Generate the key that is used to identify duplicate messages when used in
  association with the trigger id.
  """
  def build_topic_partition_offset(%Broadway.Message{metadata: metadata}) do
    %{topic: topic, partition: partition, offset: offset} = metadata

    "#{topic}_#{partition}_#{offset}"
  end

  def enable_disable_triggers(triggers) do
    supervisor = GenServer.whereis(:kafka_pipeline_supervisor)

    triggers
    |> Enum.filter(&(&1.type == :kafka))
    |> Enum.each(fn
      %{enabled: true} = trigger ->
        spec = generate_pipeline_child_spec(trigger)
        Supervisor.start_child(supervisor, spec)

      %{enabled: false} = trigger ->
        Supervisor.terminate_child(supervisor, trigger.id)
        Supervisor.delete_child(supervisor, trigger.id)
    end)
  end

  @doc """
  Generate the child spec needed to start a `Pipeline` child process.
  """
  def generate_pipeline_child_spec(trigger, reset \\ false) do
    %{
      connect_timeout: connect_timeout,
      group_id: group_id,
      hosts: hosts_list,
      password: password,
      sasl: sasl_type,
      ssl: ssl,
      topics: topics,
      username: username
    } = trigger.kafka_configuration

    hosts =
      hosts_list
      |> Enum.map(fn [host, port_string] ->
        {host, port_string |> String.to_integer()}
      end)

    sasl =
      if sasl_type do
        {sasl_type, username, password}
      else
        nil
      end

    begin_offset = if reset, do: :reset, else: :assigned

    offset_reset_policy = determine_offset_reset_policy(trigger)

    number_of_consumers = Lightning.Config.kafka_number_of_consumers()
    number_of_processors = Lightning.Config.kafka_number_of_processors()

    %{
      id: trigger.id,
      start: {
        Lightning.KafkaTriggers.Pipeline,
        :start_link,
        [
          [
            begin_offset: begin_offset,
            connect_timeout: connect_timeout * 1000,
            group_id: group_id,
            hosts: hosts,
            number_of_consumers: number_of_consumers,
            number_of_processors: number_of_processors,
            offset_reset_policy: offset_reset_policy,
            rate_limit: convert_rate_limit(),
            sasl: sasl,
            ssl: ssl,
            topics: topics,
            # sobelow_skip ["StringToAtom"]
            trigger_id: trigger.id |> String.to_atom()
          ]
        ]
      },
      restart: :transient
    }
  end

  def get_kafka_triggers_being_updated(changeset) do
    changeset
    |> Changeset.fetch_change(:triggers)
    |> case do
      :error ->
        []

      {:ok, triggers} ->
        triggers
    end
    |> Enum.filter(fn changeset ->
      {_data_or_change, type} =
        changeset
        |> Changeset.fetch_field(:type)

      type == :kafka
    end)
    |> Enum.map(fn changeset ->
      {_data_or_change, id} = Changeset.fetch_field(changeset, :id)
      id
    end)
  end

  def update_pipeline(supervisor, trigger_id) do
    Trigger
    |> Repo.get_by(id: trigger_id, type: :kafka)
    |> case do
      nil ->
        nil

      %{enabled: true} = trigger ->
        spec = generate_pipeline_child_spec(trigger)

        case Supervisor.start_child(supervisor, spec) do
          {:error, {:already_started, _pid}} ->
            Supervisor.terminate_child(supervisor, trigger.id)
            Supervisor.delete_child(supervisor, trigger.id)
            Supervisor.start_child(supervisor, spec)

          {:error, :already_present} ->
            Supervisor.delete_child(supervisor, trigger.id)
            Supervisor.start_child(supervisor, spec)

          response ->
            response
        end

      %{enabled: false} = trigger ->
        Supervisor.terminate_child(supervisor, trigger.id)
        Supervisor.delete_child(supervisor, trigger.id)
    end
  end

  def convert_rate_limit do
    per_second = Lightning.Config.kafka_number_of_messages_per_second()

    seconds_in_interval = 10

    messages_per_interval = (per_second * seconds_in_interval) |> trunc()

    %{interval: 10_000, messages_per_interval: messages_per_interval}
  end

  def test_persistence_failure?(trigger_id) do
    Trigger
    |> Repo.get(trigger_id)
    |> case do
      %{kafka_configuration: %{performed_persistence_failure_test: true}} ->
        false

      %{type: :kafka} ->
        Lightning.Config.kafka_test_persistence_failure?()

      _trigger ->
        false
    end
  end

  def tested_persistence_failure(trigger_id) do
    update_tested_persistence_failure(trigger_id, true)
  end

  def clear_tested_persistence_failure(trigger_id) do
    update_tested_persistence_failure(trigger_id, false)
  end

  defp update_tested_persistence_failure(trigger_id, performed) do
    Trigger
    |> Repo.get(trigger_id)
    |> Trigger.kafka_performed_persistence_failure_test_changeset(performed)
    |> Repo.update()
  end

  def reset_trigger(trigger_id) do
    :kafka_pipeline_supervisor
    |> GenServer.whereis()
    |> find_child_process(trigger_id)
    |> setup_trigger_reset(trigger_id)
  end

  defp find_child_process(nil, _trigger_id), do: nil

  defp find_child_process(supervisor, trigger_id) do
    supervisor
    |> Supervisor.which_children()
    |> Enum.find(fn {id, _pid, _type, _modules} -> id == trigger_id end)
  end

  defp setup_trigger_reset(nil, _trigger_id), do: nil

  defp setup_trigger_reset({_id, pid, _type, _modules}, trigger_id) do
    GenServer.stop(pid, :normal, 1000)

    IO.puts "WTAF BATMAN"
    IO.inspect(pid, label: :pid)
    IO.inspect(trigger_id, label: :trigger_id)

    Process.send_after(
      Lightning.KafkaTriggers.PipelineResetter,
      {:reset, trigger_id},
      Lightning.Config.kafka_reset_delay_seconds() * 1000
    ) |> IO.inspect(label: :send_after)
  end

  def reset_pipeline(trigger_id) do
    with supervisor when not is_nil(supervisor) <-
           GenServer.whereis(:kafka_pipeline_supervisor),
         trigger when not is_nil(trigger) <- Repo.get(Trigger, trigger_id) do
      child_spec = generate_pipeline_child_spec(trigger, true)

      Supervisor.delete_child(supervisor, trigger_id) |> IO.inspect(label: :delete_result)
      Supervisor.start_child(supervisor, child_spec) |> IO.inspect(label: :start_result)
    end
  end
end
