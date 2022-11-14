defmodule Lightning.RunSearchForm do
  use Ecto.Schema

  embedded_schema do
    field :before, :utc_datetime_usec
    field :after, :utc_datetime_usec
    field :workflow_id, :string
    # we'll need this one
    embeds_one :workflow, Lightning.Workflows.Workflow
    embeds_many :options, Lightning.RunSearchForm.RunStatusOption
  end

  defmodule RunStatusOption do
    use Ecto.Schema

    embedded_schema do
      field :selected, :boolean, default: false
      field :label, :string
    end
  end
end
