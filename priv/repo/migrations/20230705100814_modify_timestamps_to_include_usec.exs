defmodule Lightning.Repo.Migrations.ModifyTimestampsToIncludeUsec do
  use Ecto.Migration

  def change do
    alter table("attempts") do
      modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
      modify :updated_at, :naive_datetime_usec, from: :naive_datetime
    end

    alter table("attempt_runs") do
      modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
      modify :updated_at, :naive_datetime_usec, from: :naive_datetime
    end

    alter table("dataclips") do
      modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
      modify :updated_at, :naive_datetime_usec, from: :naive_datetime
    end

    alter table("runs") do
      modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
      modify :updated_at, :naive_datetime_usec, from: :naive_datetime
    end

    alter table("work_orders") do
      modify :inserted_at, :naive_datetime_usec, from: :naive_datetime
      modify :updated_at, :naive_datetime_usec, from: :naive_datetime
    end
  end
end
