defmodule Lightning.Workflows.Trigger.KafkaConfiguration do
  use Ecto.Schema
  import Ecto.Changeset

  @derive {Jason.Encoder, only: [
    :group_id,
    :hosts,
    :initial_offset_reset_policy,
    :partition_timestamps,
    :password,
    :sasl,
    :ssl,
    :topics,
    :username
  ]}

  embedded_schema do
    field :group_id, :string
    field :hosts, {:array, {:array, :string}}
    field :hosts_string, :string, virtual: true
    field :initial_offset_reset_policy, :string
    field :partition_timestamps, :map
    field :password, :string
    field :sasl, :string
    field :ssl, :boolean
    field :topics, {:array, :string}
    field :topics_string, :string, virtual: true
    field :username, :string
  end

  def changeset(kafka_configuration, attrs) do
    kafka_configuration
    |> cast(attrs, [
      :group_id,
      :hosts,
      :initial_offset_reset_policy,
      :partition_timestamps,
      :password,
      :sasl,
      :ssl,
      :topics,
      :username
    ])
    |> apply_hosts_string(attrs)
    |> apply_topics_string(attrs)
  end

  def generate_hosts_string(changeset) do
    hosts_string =
      changeset
      |> get_field(:hosts)
      |> Enum.map(fn [host, port] -> "#{host}:#{port}" end)
      |> Enum.join(", ")

    changeset
    |> put_change(:hosts_string, hosts_string)
  end

  def generate_topics_string(changeset) do
    topics_string =
      changeset
      |> get_field(:topics)
      |> Enum.join(", ")

    changeset
    |> put_change(:topics_string, topics_string)
  end

  def apply_hosts_string(changeset, attrs) do
    case attrs[:hosts_string] do
      nil ->
        changeset
      "" ->
        changeset |> put_change(:hosts, [])
      hosts_string ->
        hosts = 
          hosts_string
          |> String.split(",")
          |> Enum.map(fn host ->
            host
            |> String.split(":")
            |> Enum.map(&String.trim/1)
          end)

        changeset |> put_change(:hosts, hosts)
    end
  end

  def apply_topics_string(changeset, attrs) do
    case attrs[:topics_string] do
      nil ->
        changeset
      "" ->
        changeset |> put_change(:topics, [])
      topics_string ->
        topics = 
          topics_string
          |> String.split(",")
          |> Enum.map(&String.trim/1)

        changeset |> put_change(:topics, topics)
    end
  end
end
