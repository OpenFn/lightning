defmodule Lightning.Repo.Migrations.InstallCarbonite do
  use Ecto.Migration

  @carbonite_prefix Application.compile_env(:lightning, :transaction_auditing, [])
                    |> Keyword.get(:schema)
  @mode Application.compile_env(:lightning, :transaction_auditing, [])
        |> Keyword.get(:enabled)
        |> if(do: :capture, else: :ignore)

  def up do
    # If you like to install Carbonite's tables into a different schema, add the
    # carbonite_prefix option.
    #
    #    Carbonite.Migrations.up(1, carbonite_prefix: "carbonite_other")
    prefix =
      Carbonite.Migrations.up(1..7, carbonite_prefix: @carbonite_prefix)

    # Install a trigger for a table:

    for table <- ["workflows", "jobs", "workflow_edges", "triggers"] do
      Carbonite.Migrations.create_trigger(table, carbonite_prefix: @carbonite_prefix)

      Carbonite.Migrations.put_trigger_config(table, :mode, @mode,
        carbonite_prefix: @carbonite_prefix
      )
    end

    # Configure trigger options:
    #
    #    Carbonite.Migrations.put_trigger_option("rabbits", :primary_key_columns, ["compound", "key"])
    #    Carbonite.Migrations.put_trigger_option("rabbits", :excluded_columns, ["private"])
    #    Carbonite.Migrations.put_trigger_option("rabbits", :filtered_columns, ["private"])
    #    Carbonite.Migrations.put_trigger_option("rabbits", :mode, :ignore)

    # If you wish to insert an initial outbox:
    #
    #    Carbonite.Migrations.create_outbox("rabbits")
    #    Carbonite.Migrations.create_outbox("rabbits", carbonite_prefix: "carbonite_other")
  end

  def down do
    for table <- ["workflows", "jobs", "workflow_edges", "triggers"] do
      Carbonite.Migrations.drop_trigger(table, carbonite_prefix: @carbonite_prefix)
    end

    Carbonite.Migrations.down(7..1, carbonite_prefix: @carbonite_prefix)
  end
end
