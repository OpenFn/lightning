defmodule Lightning.RunSearchForm do
  @moduledoc """
  Run filtering search form.
  """
  use Ecto.Schema

  embedded_schema do
    field :search_term, :string
    field :date_before, :utc_datetime_usec
    field :date_after, :utc_datetime_usec
    field :wo_date_before, :utc_datetime_usec
    field :wo_date_after, :utc_datetime_usec
    field :workflow_id, :string
    embeds_one :workflow, Lightning.Workflows.Workflow
    embeds_many :status_options, Lightning.RunSearchForm.MultiSelectOption
    embeds_many :searchfor_options, Lightning.RunSearchForm.MultiSelectOption
  end

  defmodule MultiSelectOption do
    @moduledoc false
    use Ecto.Schema

    embedded_schema do
      field :selected, :boolean, default: false
      field :label, :string
    end
  end
end
