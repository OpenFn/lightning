defmodule Lightning.Repo.Migrations.DropInvocationEvents do
  use Ecto.Migration

  def change do
    drop table("invocation_events")
  end
end
