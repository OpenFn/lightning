defmodule Lightning.LiveViewHelpers do
  @doc """
  Get a given components assign by querying the state of the LiveView
  """
  def get_component_assigns_by(live, id: id) do
    {comp, _, _} = :sys.get_state(live.pid) |> Map.get(:components)

    comp
    |> Enum.reduce(nil, fn {_cid, {mod, actual_id, assigns, _changed, _diff}},
                           found ->
      case {actual_id, found} do
        {^id, nil} ->
          {mod, assigns}

        {_, _} ->
          found
      end
    end)
  end
end
