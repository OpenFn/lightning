defmodule Lightning.Repo.Migrations.ModifyRunsExitReason do
  use Ecto.Migration

  def up do
    # set exit_reason back to fail before next release for new worker contract
    execute(
      fn ->
        repo().query!(
          """
          UPDATE runs
          SET exit_reason = 'fail'
          WHERE runs.exit_reason = 'error';
          """,
          [],
          log: :info
        )
      end,
      ""
    )
  end

  def down do
    # set exit_reason back to error
    execute(
      fn ->
        repo().query!(
          """
          UPDATE runs
          SET exit_reason = 'error'
          WHERE runs.exit_reason = 'fail';
          """,
          [],
          log: :info
        )
      end,
      ""
    )
  end
end
