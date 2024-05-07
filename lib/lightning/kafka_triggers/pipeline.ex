defmodule Lightning.KafkaTriggers.Pipeline do
  use Broadway

  def start_link(opts) do
    name = opts |> Keyword.get(:name)

    Broadway.start_link(__MODULE__,
      name: name,
      context: %{
        name: name
      },
      producer: [
        module:
          {
            BroadwayKafka.Producer,
            build_producer_opts(opts)
          },
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: 10
        ]
      ],
      batchers: []
    )
  end

  def handle_message(_processor, message, context) do
    %{name: name} = context
    %Broadway.Message{data: data, metadata: %{ts: ts}} = message

    IO.puts(">>>> #{name} received #{data} produced at #{ts}")
    # IO.inspect(message) 
    # Need to return the message
    message
  end

  defp build_producer_opts(opts) do
    hosts = opts |> Keyword.get(:hosts)
    group_id = opts |> Keyword.get(:group_id)
    topics = opts |> Keyword.get(:topics)

    [
      client_config: client_config(opts),
      hosts: hosts,
      group_id: group_id,
      topics: topics,
      offset_reset_policy: :earliest,
    ]
  end

  defp client_config(opts) do
    sasl = opts |> Keyword.get(:sasl)

    case sasl do
      nil ->
        []
      sasl ->
        {mechanism, username, password} = sasl
        # [{:client_config, [{:sasl, {String.to_atom(mechanism), username, password}}, {:ssl, true}]} | base_opts]
        [{:sasl, {String.to_atom(mechanism), username, password}}]
    end
  end
end
