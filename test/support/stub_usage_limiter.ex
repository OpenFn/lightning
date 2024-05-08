defmodule Lightning.Extensions.StubUsageLimiter do
  @behaviour Lightning.Extensions.UsageLimiting

  alias Lightning.Extensions.Message

  defmodule Banner do
    use LightningWeb, :component

    def text(assigns) do
      ~H"""
      <div>
        Some banner text
      </div>
      """
    end
  end

  @impl true
  def check_limits(_context) do
    {:error, :too_many_runs,
     %Message{
       position: :banner,
       function: &Banner.text/1,
       attrs: %{},
       text: nil
     }}
  end

  @impl true
  def limit_action(_action, _context) do
    {:error, :too_many_runs, %Message{text: "Runs limit exceeded"}}
  end

  @impl true
  def get_run_options(_context), do: []
end
