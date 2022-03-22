defmodule Lightning.Repo.Migrations.AddAdaptorToJob do
  use Ecto.Migration

  def change do
    alter table("jobs") do
      add :adaptor, :string
    end
  end
end
