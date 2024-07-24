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
        initial_policy |> String.to_existing_atom()

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
  def generate_pipeline_child_spec(trigger) do
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

    offset_reset_policy = determine_offset_reset_policy(trigger)

    number_of_consumers =
      Application.get_env(:lightning, :kafka_triggers)[:number_of_consumers]

    %{
      id: trigger.id,
      start: {
        Lightning.KafkaTriggers.Pipeline,
        :start_link,
        [
          [
            number_of_consumers: number_of_consumers,
            connect_timeout: connect_timeout * 1000,
            group_id: group_id,
            hosts: hosts,
            offset_reset_policy: offset_reset_policy,
            # sobelow_skip ["StringToAtom"]
            trigger_id: trigger.id |> String.to_atom(),
            sasl: sasl,
            ssl: ssl,
            topics: topics
          ]
        ]
      }
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
end
