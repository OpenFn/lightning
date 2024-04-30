defmodule Lightning.KafkaTriggers.Pipeline do
  use Broadway

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    hosts = Keyword.get(opts, :hosts)
    group_id = Keyword.get(opts, :group_id)
    topics = Keyword.get(opts, :topics)

    Broadway.start_link(__MODULE__,
      name: name,
      context: %{
        name: name
      },
      producer: [
        module:
          {
            BroadwayKafka.Producer,
            [
              hosts: hosts,
              group_id: group_id,
              topics: topics,
              offset_reset_policy: :earliest
            ]
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
end
