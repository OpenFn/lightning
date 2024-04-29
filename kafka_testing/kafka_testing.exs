Mix.install([
  {:broadway_kafka, "~> 0.4.2"}
])

hosts = [
  localhost: 9096,
  localhost: 9095,
  localhost: 9094
]

# For single container testing, use the following:
# hosts = [localhost: 9092]

defmodule KafkaPipeline do
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

defmodule PipelineSupervisor do
  use Supervisor

  def start_link(opts, hosts) do
    Supervisor.start_link(__MODULE__, hosts, opts)
  end

  @impl true
  def init(hosts) do
    children = [
      %{
        id: "foo_child",
        start: {
          KafkaPipeline,
          :start_link,
          [
            [ 
              name: :foo_pipeline,
              hosts: hosts,
              group_id: "foo_group",
              topics: ["foo_topic"]
            ]
          ]
        }
      },
      %{
        id: "bar_child",
        start: {
          KafkaPipeline,
          :start_link,
          [
            [ 
              name: :bar_pipeline,
              hosts: hosts,
              group_id: "bar_group",
              topics: ["bar_topic"]
            ]
          ]
        }
      },
      %{
        id: "baz_child",
        start: {
          KafkaPipeline,
          :start_link,
          [
            [ 
              name: :baz_pipeline,
              hosts: hosts,
              group_id: "baz_group",
              topics: ["baz_topic"]
            ]
          ]
        }
      },
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end

{:ok, sup} = PipelineSupervisor.start_link([], hosts)

:timer.sleep(5000)

IO.puts("Adding the boz consumer group")

Supervisor.start_child(sup, %{
  id: "boz_child",
  start: {
    KafkaPipeline,
    :start_link,
    [
      [ 
        name: :boz_pipeline,
        hosts: hosts,
        group_id: "boz_group",
        topics: ["boz_topic"]
      ]
    ]
  }
})

:timer.sleep(30000)

IO.puts("Bad boz! No more messages for you")

:ok = Supervisor.terminate_child(sup, "boz_child")
:ok = Supervisor.delete_child(sup, "boz_child")

:timer.sleep(600000)
