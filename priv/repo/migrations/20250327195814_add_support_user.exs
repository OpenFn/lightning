defmodule Lightning.Repo.Migrations.AddSupportUser do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add :support_user, :boolean, default: false
    end

    alter table(:projects) do
      add :allow_support_access, :boolean, default: false
    end
  end
end
