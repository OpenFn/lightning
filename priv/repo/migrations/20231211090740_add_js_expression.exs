defmodule Lightning.Repo.Migrations.AddJsExpression do
  use Ecto.Migration

  def change do
    alter table(:workflow_edges) do
      add :condition_expression, :string
      add :condition_label, :string
    end

    rename table(:workflow_edges), :condition, to: :condition_type
  end
end
