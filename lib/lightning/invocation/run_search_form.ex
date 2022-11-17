defmodule Lightning.RunSearchForm do
  @moduledoc """
  Run filtering serach form.
  """
  use Ecto.Schema

  embedded_schema do
    field :date_before, :utc_datetime_usec
    field :date_after, :utc_datetime_usec
    field :workflow_id, :string
    embeds_one :workflow, Lightning.Workflows.Workflow
    embeds_many :options, Lightning.RunSearchForm.RunStatusOption
  end

  defmodule RunStatusOption do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field :selected, :boolean, default: false
      field :label, :string
    end
  end
end
