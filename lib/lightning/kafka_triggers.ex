defmodule Lightning.KafkaTriggers do
  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Workflows.Trigger

  def find_enabled_triggers do
    query =
      from t in Trigger,
      where: t.type == :kafka,
      where: t.enabled == true

    query |> Repo.all()
  end
end
