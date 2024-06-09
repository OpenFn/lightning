defmodule Lightning.Workflows.Trigger.KafkaConfiguration do
  use Ecto.Schema
  import Ecto.Changeset

  @sasl_types [:plain, :scram_sha_256, :scram_sha_512]

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
    field :partition_timestamps, :map, default: %{}
    field :password, Lightning.Encrypted.Binary
    field :sasl, Ecto.Enum, values: @sasl_types, default: nil
    field :ssl, :boolean
    field :topics, {:array, :string}
    field :topics_string, :string, virtual: true
    field :username, Lightning.Encrypted.Binary
  end

  def changeset(kafka_configuration, attrs) do
    kafka_configuration
    |> cast(attrs, [
      :group_id,
      :hosts,
      :hosts_string,
      :initial_offset_reset_policy,
      :partition_timestamps,
      :password,
      :sasl,
      :ssl,
      :topics,
      :topics_string,
      :username
    ])
    |> apply_hosts_string()
    |> apply_topics_string()
    |> apply_password(kafka_configuration)
  end

  def apply_password(changeset, kafka_configuration) do
    # TODO No longer needed - just need to handle the case for nil or empty
    # string
    new_password =
      changeset
      |> get_field(:password)
      |> case do
        nil ->
          kafka_configuration.password
        "" ->
          kafka_configuration.password
        "********************" ->
          kafka_configuration.password
        password ->
          password
      end

    changeset
    |> put_change(:password, new_password)
  end

  def generate_hosts_string(changeset) do
    hosts_string =
      changeset
      |> get_field(:hosts)
      |> case do
        nil ->
          ""
        hosts ->
          hosts
          |> Enum.map(fn
            [host, port] -> "#{host}:#{port}"
            #TODO something_else is a bandaid for a live validation issue
            # make a better plan
            something_else -> something_else
          end)
          |> Enum.join(", ")
      end

    changeset
    |> put_change(:hosts_string, hosts_string)
  end

  def generate_topics_string(changeset) do
    topics_string =
      changeset
      |> get_field(:topics)
      |> case do
        nil ->
          ""
        topics ->
          topics
          |> Enum.join(", ")
      end

    changeset
    |> put_change(:topics_string, topics_string)
  end

  def apply_hosts_string(changeset) do
    case get_field(changeset, :hosts_string) do
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
            |> case do
              [host, port] -> [host, port]
              #TODO something_else is a bandaid for a live validation issue
              # make a better plan
              something_else -> something_else
            end
            |> Enum.map(&String.trim/1)
          end)

        changeset |> put_change(:hosts, hosts)
    end
  end

  def apply_topics_string(changeset) do
    case get_field(changeset, :topics_string) do
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

  def sasl_types, do: @sasl_types |> Enum.map(&Atom.to_string(&1))
end
