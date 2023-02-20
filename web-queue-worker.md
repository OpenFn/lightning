# Sequence Diagram Job Execution via "Web Queue Worker" Architecture.

Draft. Note that this architecture is only for the final `:runs` queue, not for fairness or limiting.

```mermaid
sequenceDiagram
autonumber
    participant L as Lightning (Elixir)
    participant Q as Queue (RabbitMQ)
    participant R as RTM (NodeJs)
    L->>Q: Enqueue attempt
    Q->>L: Respond with {:attempt_enqued, uuid}
    R->>Q: Take oldest attempt
    R->>L: Notify {:attempt_accepted, uuid}
    loop for each run in attempt
    Note over L,R: by allowing the same worker to take a whole "attempt" <br> we guarantee order of execution _and_ may find efficiencies <br> by maintaining the same NodeVM for all runs <br> inside an attempt, passing state between runs, etc.
    R->>L: Fetch artifacts for run {state, expression}
    R->>L: Notify {:run_started, uuid} for run
    R->>L: Stream logs {:log_line_emitted, run_uuid, log_line}
    R->>L: Notify {:run_finished | :run_crashed, uuid, stats}
    end
    loop every 10s
    Note over R,L: Heartbeat so Lightning knows if an RTM crashes?
    R->>L: Notify {:attempt_heartbeat, uuid}
    end
    R->>L: Notify {:attempt_finished, uuid}
    loop every 30s
    L->>R: Check status of attempts with no heartbeat
    L->>L: Mark orphaned runs as {:crashed, uuid}
    end
```

## Lightning

### APIs

1. `GET` for job-run artifacts (state, expression) which can be accessed by the subscriber RTM.
2. `POST` for streaming logs for a given run.
3. `POST` for status update (`{:accepted, :started, :running, :done, :crashed}`) for a given run.

## RTM

1. The RTM should take `N` number of runs at any given time, probably related to how many cores/threads it has access to?
2. The number of RTMs (subscribers) should be scaled up and down based on utilization.

### APIs 

Should this be a Koa app with some APIs? (Healthcheck? Status of attempt X?)

1. Is there an API for RTM application health?
2. And another for the status of a particular run? (Useful to call if the heartbeat fails?)
