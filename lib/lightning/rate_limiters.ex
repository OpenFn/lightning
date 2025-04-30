defmodule Lightning.RateLimiters do
  @moduledoc false

  defmodule Mail do
    @moduledoc false

    # WARNING: When changing the algorithm, you must also update the mnesia table name.
    # The default is to use __MODULE__, passing `:table` to the `use Hammer` macro
    # allows you to specify a custom table name.
    use Hammer,
      backend: Hammer.Mnesia,
      algorithm: :leaky_bucket,
      table: :mail_limiter

    @type hit_result ::
            {:allow,
             %{
               count: non_neg_integer(),
               time_scale: non_neg_integer(),
               rate_limit: non_neg_integer()
             }}
            | {:deny, non_neg_integer()}
  end

  @spec hit({:failure_email, String.t(), String.t()}) :: Mail.hit_result()
  def hit({:failure_email, workflow_id, user_id}) do
    [time_scale: time_scale, rate_limit: rate_limit] =
      Application.fetch_env!(:lightning, Lightning.FailureAlerter)

    Mail.hit("#{workflow_id}::#{user_id}", time_scale, rate_limit)
    |> case do
      {:allow, count} ->
        {:allow, %{count: count, time_scale: time_scale, rate_limit: rate_limit}}

      {:deny, count} ->
        {:deny, count}
    end
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  def start_link(opts) do
    children = [{Mail, opts}]
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
