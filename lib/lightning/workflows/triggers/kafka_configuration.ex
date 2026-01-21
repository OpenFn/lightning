defmodule Lightning.Workflows.Triggers.KafkaConfiguration do
  @moduledoc """
  Configuration of Kafka Triggers.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @sasl_types [:plain, :scram_sha_256, :scram_sha_512]

  @derive {Jason.Encoder,
           only: [
             :group_id,
             :hosts,
             :initial_offset_reset_policy,
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
    field :password, Lightning.Encrypted.EmbeddedBinary
    field :sasl, Ecto.Enum, values: @sasl_types, default: nil
    field :ssl, :boolean
    field :topics, {:array, :string}
    field :topics_string, :string, virtual: true
    field :username, Lightning.Encrypted.EmbeddedBinary
  end

  def changeset(kafka_configuration, attrs) do
    kafka_configuration
    |> cast(attrs, [
      :connect_timeout,
      :hosts,
      :hosts_string,
      :initial_offset_reset_policy,
      :password,
      :sasl,
      :ssl,
      :topics,
      :topics_string,
      :username
    ])
    |> apply_hosts_string()
    |> apply_topics_string()
    |> validate_required([
      :connect_timeout,
      :hosts,
      :initial_offset_reset_policy,
      :topics
    ])
    |> validate_length(:hosts, min: 1)
    |> validate_length(:topics, min: 1)
    |> validate_initial_offset_reset_policy()
    |> set_group_id_if_required()
    |> validate_sasl_credentials()
    |> validate_number(:connect_timeout, greater_than: 0)
  end

  def generate_hosts_string(%Ecto.Changeset{} = changeset) do
    hosts_string =
      changeset
      |> get_field(:hosts)
      |> generate_hosts_string()

    changeset
    |> put_change(:hosts_string, hosts_string)
  end

  def generate_hosts_string(hosts) do
    case hosts do
      nil ->
        ""

      hosts when is_list(hosts) ->
        Enum.map_join(
          hosts,
          ", ",
          fn
            [host, port] -> "#{host}:#{port}"
            something_else -> something_else
          end
        )
    end
  end

  def generate_topics_string(%Ecto.Changeset{} = changeset) do
    topics_string =
      changeset
      |> get_field(:topics)
      |> generate_topics_string()

    changeset
    |> put_change(:topics_string, topics_string)
  end

  def generate_topics_string(topics) do
    case topics do
      nil ->
        ""

      topics when is_list(topics) ->
        Enum.join(topics, ", ")
    end
  end

  def apply_hosts_string(changeset) do
    case get_field(changeset, :hosts_string) do
      nil ->
        changeset |> check_for_existing_hosts()

      "" ->
        changeset
        |> add_error(
          :hosts_string,
          "Must be specified in the format `host:port, host:port`"
        )

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

          _some_errors ->
            changeset
            |> add_error(
              :hosts_string,
              "Must be specified in the format `host:port, host:port`"
            )
        end
    end
  end

  defp check_for_existing_hosts(changeset) do
    case get_field(changeset, :hosts) do
      nil ->
        changeset
        |> add_error(
          :hosts_string,
          "Must be specified in the format `host:port, host:port`"
        )

      [] ->
        changeset
        |> add_error(
          :hosts_string,
          "Must be specified in the format `host:port, host:port`"
        )

      _hosts ->
        changeset
    end
  end

  def apply_topics_string(changeset) do
    case get_field(changeset, :topics_string) do
      nil ->
        case get_field(changeset, :topics) do
          nil ->
            changeset
            |> add_error(
              :topics_string,
              "Must be specified in the format `topic_1, topic_2`"
            )

          [] ->
            changeset
            |> add_error(
              :topics_string,
              "Must be specified in the format `topic_1, topic_2`"
            )

          _topics ->
            changeset
        end

      "" ->
        changeset
        |> add_error(
          :topics_string,
          "Must be specified in the format `topic_1, topic_2`"
        )

      topics_string ->
        topics_string
        |> String.split(",")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> case do
          [] ->
            changeset
            |> add_error(
              :topics_string,
              "Must be specified in the format `topic_1, topic_2`"
            )

          topics ->
            changeset |> put_change(:topics, topics)
        end
    end
  end

  def validate_initial_offset_reset_policy(changeset) do
    case get_change(changeset, :initial_offset_reset_policy) do
      nil ->
        changeset

      policy ->
        trimmed_policy = String.trim(policy)

        cond do
          trimmed_policy in ["earliest", "latest"] ->
            changeset |> put_change(:initial_offset_reset_policy, trimmed_policy)

          String.match?(trimmed_policy, ~r/^\d{13}$/) ->
            changeset |> put_change(:initial_offset_reset_policy, trimmed_policy)

          true ->
            changeset
            |> add_error(
              :initial_offset_reset_policy,
              "must be `earliest`, `latest` or timestamp with millisecond " <>
                "precision (e.g. `1720428955123`)"
            )
        end
    end
  end

  def validate_sasl_credentials(changeset) do
    changeset
    |> get_field(:sasl)
    |> case do
      nil ->
        changeset |> check_for_superfluous_credentials()

      _sasl_type ->
        changeset |> check_for_required_credentials()
    end
  end

  defp check_for_superfluous_credentials(changeset) do
    changeset =
      changeset
      |> get_field(:password)
      |> case do
        nil ->
          changeset

        _password ->
          changeset
          |> add_error(:password, "Requires SASL to be selected")
      end

    changeset
    |> get_field(:username)
    |> case do
      nil ->
        changeset

      _username ->
        changeset
        |> add_error(:username, "Requires SASL to be selected")
    end
  end

  defp check_for_required_credentials(changeset) do
    changeset =
      changeset
      |> get_field(:password)
      |> case do
        nil ->
          changeset
          |> add_error(:password, "Required if SASL is selected")

        _password ->
          changeset
      end

    changeset
    |> get_field(:username)
    |> case do
      nil ->
        changeset
        |> add_error(:username, "Required if SASL is selected")

      _username ->
        changeset
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
end
