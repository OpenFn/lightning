defmodule Lightning.RunSearchForm do
  use Ecto.Schema

  embedded_schema do
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
