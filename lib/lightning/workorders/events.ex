defmodule Lightning.Workorders.Events do
  @moduledoc false

  defmodule AttemptCreated do
    @moduledoc false
    defstruct attempt: nil
  end

  defmodule AttemptUpdated do
    @moduledoc false
    defstruct attempt: nil
  end

  defmodule RunUpdated do
    @moduledoc false
    defstruct run: nil
  end
end
