defmodule Lightning.Workflows.Triggers.KafkaConfiguration do
  use Ecto.Schema
  import Ecto.Changeset

  @sasl_types [:plain, :scram_sha_256, :scram_sha_512]

  @derive {Jason.Encoder,
           only: [
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
    field :connect_timeout, :integer, default: 30
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
      :connect_timeout,
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
    |> validate_required([
      :connect_timeout,
      :hosts_string,
      :initial_offset_reset_policy,
      :topics_string
    ])
    |> apply_hosts_string()
    |> apply_topics_string()
    |> set_group_id_if_required()
    |> validate_sasl_credentials()
    |> validate_number(:connect_timeout, greater_than: 0)
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
            # TODO something_else is a bandaid for a live validation issue
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
        [hosts, errors] =
          hosts_string
          |> String.split(",")
          |> Enum.reduce([[], []], fn host, [hosts, errors] ->
            host
            |> String.split(":")
            |> case do
              [host, port] ->
                trimmed_set =
                  [host, port]
                  |> Enum.map(&String.trim/1)

                [[trimmed_set | hosts], errors]

              _incorrect_result ->
                [hosts, [host | errors]]
            end
          end)

        case errors do
          [] ->
            changeset |> put_change(:hosts, hosts |> Enum.reverse())

          _ ->
            changeset
            |> add_error(
              :hosts_string,
              "Must be specified in the format `host:port, host:port`"
            )
        end
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

  def validate_sasl_credentials(changeset) do
    changeset
    |> get_field(:sasl)
    |> case do
      nil ->
        changeset =
          case get_field(changeset, :password) do
            nil ->
              changeset

            _ ->
              changeset
              |> add_error(:password, "Requires SASL to be selected")
          end

        case get_field(changeset, :username) do
          nil ->
            changeset

          _ ->
            changeset
            |> add_error(:username, "Requires SASL to be selected")
        end

      _sasl_type ->
        changeset =
          case get_field(changeset, :password) do
            nil ->
              changeset
              |> add_error(:password, "Required if SASL is selected")

            _ ->
              changeset
          end

        case get_field(changeset, :username) do
          nil ->
            changeset
            |> add_error(:username, "Required if SASL is selected")

          _ ->
            changeset
        end
    end
  end

  def sasl_types, do: @sasl_types |> Enum.map(&Atom.to_string(&1))

  def set_group_id_if_required(changeset) do
    changeset
    |> delete_change(:group_id)
    |> case do
      set = %{data: %{group_id: nil}} ->
        set |> put_change(:group_id, "lightning-#{Ecto.UUID.generate()}")

      set ->
        set
    end
  end

  @doc """
  Returns a changeset to maintain persisted partition timestamps. These
  timestamps are used to provide an updated offset reset policy should the
  associated consumer group have been used previously but has not connected to
  the cluster for a long enough time that the cluster no longer has a committed
  offset.
  """
  def partitions_changeset(configuration, partition, timestamp) do
    partition_key = partition |> Integer.to_string()

    %{
      partition_timestamps: partition_timestamps
    } = configuration

    updated_partition_timestamps =
      partition_timestamps
      |> case do
        existing = %{^partition_key => existing_timestamp}
        when existing_timestamp < timestamp ->
          existing |> Map.merge(%{partition_key => timestamp})

        existing = %{^partition_key => _existing_timestamp} ->
          existing

        existing ->
          existing |> Map.merge(%{partition_key => timestamp})
      end

    # TODO Rearrange changeset so that we do not the *_string values
    configuration
    |> changeset(%{
      hosts_string: hosts_string_from(configuration),
      partition_timestamps: updated_partition_timestamps,
      topics_string: topics_string_from(configuration)
    })
  end

  # TODO Centralise the below two methods and test
  defp hosts_string_from(kafka_configuration) do
    kafka_configuration.hosts
    |> case do
      nil ->
        ""

      hosts ->
        hosts
        |> Enum.map(fn
          [host, port] -> "#{host}:#{port}"
          # TODO something_else is a bandaid for a live validation issue
          # make a better plan
          something_else -> something_else
        end)
        |> Enum.join(", ")
    end
  end

  defp topics_string_from(kafka_configuration) do
    kafka_configuration.topics
    |> case do
      nil ->
        ""

      topics ->
        topics
        |> Enum.join(", ")
    end
  end
end
