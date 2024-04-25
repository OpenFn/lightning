Mix.install([
  {:broadway_kafka, "~> 0.4.2"}
])

defmodule KafkaPipeline do
  use Broadway

  def start_link(opts) do
    name = Keyword.get(opts, :name)
    hosts = Keyword.get(opts, :hosts)
    group_id = Keyword.get(opts, :group_id)
    topics = Keyword.get(opts, :topics)

    Broadway.start_link(__MODULE__,
      name: name,
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

  def handle_message(_processor, message, _context) do
    IO.inspect(message) 
  end
end

defmodule PipelineSupervisor do
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    children = [
      %{
        id: "foo_child",
        start: {
          KafkaPipeline,
          :start_link,
          [
            [ 
              name: :foo_pipeline,
              hosts: [localhost: 9096, localhost: 9095, localhost: 9094],
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
              hosts: [localhost: 9096, localhost: 9095, localhost: 9094],
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
              hosts: [localhost: 9096, localhost: 9095, localhost: 9094],
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

{:ok, sup} = PipelineSupervisor.start_link([])

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
        hosts: [localhost: 9096, localhost: 9095, localhost: 9094],
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
