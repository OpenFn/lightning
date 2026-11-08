defmodule Lightning.Repo.Migrations.CreateOrganizations do
  use Ecto.Migration

  # An organization sits above projects: every project belongs to one, and a
  # person can belong to many. An instance that already has projects gets one
  # organization holding all of them, with its superusers as admins and every
  # project member as a member. Membership opens no project, so nobody can
  # reach anything they couldn't before.
  def up do
    create table(:organizations, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create table(:organization_users, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :role, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:organization_users, [:organization_id, :user_id])
    create index(:organization_users, [:user_id])

    alter table(:projects) do
      add :organization_id,
          references(:organizations, type: :binary_id, on_delete: :restrict)
    end

    create index(:projects, [:organization_id])

    execute """
    WITH organization AS (
      INSERT INTO organizations (id, name, inserted_at, updated_at)
      SELECT gen_random_uuid(), 'Default organization',
             date_trunc('second', now() AT TIME ZONE 'utc'),
             date_trunc('second', now() AT TIME ZONE 'utc')
      WHERE EXISTS (SELECT 1 FROM projects)
      RETURNING id, inserted_at
    ), moved AS (
      UPDATE projects SET organization_id = organization.id
      FROM organization
      RETURNING projects.id
    )
    INSERT INTO organization_users
      (id, organization_id, user_id, role, inserted_at, updated_at)
    SELECT gen_random_uuid(), organization.id, people.user_id, people.role,
           organization.inserted_at, organization.inserted_at
    FROM organization,
      (SELECT id AS user_id, 'admin' AS role FROM users WHERE role = 'superuser'
       UNION
       SELECT DISTINCT pu.user_id, 'member'
       FROM project_users pu
       JOIN users u ON u.id = pu.user_id
       WHERE u.role <> 'superuser') AS people
    """
  end

  def down do
    alter table(:projects) do
      remove :organization_id
    end

    drop table(:organization_users)
    drop table(:organizations)
  end
end
