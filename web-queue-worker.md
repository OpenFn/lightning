# Sequence Diagram Job Execution via "Web Queue Worker" Architecture.

Draft. Note that this architecture is only for the final `:runs` queue, not for fairness or limiting.

```mermaid
sequenceDiagram
autonumber
    participant L as Lightning (Elixir)
    participant Q as Queue (RabbitMQ)
    participant R as RTM (NodeJs)
    L->>Q: Enqueue run
    Q->>L: Respond with {:enqued, uuid}
    R->>Q: Take oldest run
    R->>L: Notify {:accepted, uuid}
    R->>L: Fetch artifacts {state, expression}
    R->>L: Notify {:started, uuid}
    R->>L: Stream logs {:uuid, log_line}
    loop every 10s
    Note over R,L: Heartbeat so Lightning knows if an RTM crashes?
    R->>L: Notify {:running, uuid}
    end
    R->>L: Notify {:done | :crashed, uuid, stats}
    loop every 30s
    L->>R: Check status of runs with no heartbeat
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
1. Is there an API for RTM application health?
2. And another for the status of a particular run? (Useful to call if the heartbeat fails?)
