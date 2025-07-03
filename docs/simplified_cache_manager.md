# Simplified Cache Manager PRD

## Overview

This PRD outlines a significant architectural simplification of the Lightning Adaptors cache management system. The core insight is that the **CacheManager should own and manage Cachex**, rather than having complex coordination between Supervisor, CacheManager, and Cachex as separate processes.

## Current Problems

### Complex Process Coordination
```
Supervisor
├── Cachex (with optional warmer configuration)
├── CacheManager (tries to coordinate with existing Cachex)
└── Registry (process management)
```

**Issues:**
- Race conditions between Cachex warmer and CacheManager startup
- Complex logic in Supervisor about when to enable warmers
- CacheManager has to work with pre-existing Cachex process
- Difficult to follow startup flow across multiple processes

### Confusing Startup Logic
```elixir
# Current complex scenarios in CacheManager
:offline_with_cache    # Restore cache, no warming
:offline_no_cache      # Fail gracefully  
:cache_exists_online   # Restore first, then warm async
:no_cache_online       # Warm synchronously (blocks)
```

## Proposed Solution

### Simplified Architecture
```
Supervisor
├── CacheManager (owns Cachex, manages warmers)
└── Registry (process management)
```

### Clean Startup Flow
```elixir
CacheManager.init()
├── handle_continue(:start_cache) → Start Cachex
├── handle_continue(:determine_warming) → Choose warming strategy
├── handle_continue(:start_file_warmer) → Restore from file (if exists)
└── handle_continue(:start_strategy_warmer) → Fetch fresh data
```

## Requirements

### FR1: CacheManager Owns Cachex
- **FR1.1**: CacheManager starts Cachex internally during initialization
- **FR1.2**: CacheManager controls Cachex lifecycle and configuration  
- **FR1.3**: No external processes interact with Cachex directly

### FR2: Simplified Startup Logic
- **FR2.1**: Cache file exists → Start file warmer (non-blocking)
- **FR2.2**: Cache file doesn't exist → Start strategy warmer (blocking)
- **FR2.3**: After strategy warmer completes → Write cache file

### FR3: Warmer Management
- **FR3.1**: CacheManager creates and manages warmer processes
- **FR3.2**: File warmer reads from cache file, populates Cachex
- **FR3.3**: Strategy warmer uses strategy to fetch fresh data
- **FR3.4**: Periodic warmer runs strategy warmer at intervals

### FR4: Staged Initialization
- **FR4.1**: Use `handle_continue` for multi-phase startup
- **FR4.2**: Non-blocking startup when cache file exists
- **FR4.3**: Graceful fallback when cache file doesn't exist

## Technical Design

### Core Architecture

```elixir
defmodule Lightning.Adaptors.CacheManager do
  use GenServer
  
  @doc """
  Starts CacheManager which owns and manages Cachex internally.
  """
  def start_link(config) do
    GenServer.start_link(__MODULE__, config, name: via_name(config.name))
  end
  
  def init(config) do
    {:ok, config, {:continue, :start_cache}}
  end
  
  def handle_continue(:start_cache, config) do
    # Start Cachex without any warmers - we'll manage them ourselves
    {:ok, _} = Cachex.start_link(config.cache, [])
    
    {:noreply, config, {:continue, :determine_warming}}
  end
  
  def handle_continue(:determine_warming, config) do
    if cache_file_exists?(config) do
      {:noreply, config, {:continue, :start_file_warmer}}
    else
      {:noreply, config, {:continue, :start_strategy_warmer}}
    end
  end
  
  def handle_continue(:start_file_warmer, config) do
    # Non-blocking: restore cache from file
    {:ok, _} = start_file_warmer(config)
    
    # After file restore, schedule strategy warmer for fresh data
    {:noreply, config, {:continue, :schedule_strategy_warmer}}
  end
  
  def handle_continue(:schedule_strategy_warmer, config) do
    # Small delay to let file warmer complete
    Process.send_after(self(), :start_strategy_warmer, 100)
    {:noreply, config}
  end
  
  def handle_continue(:start_strategy_warmer, config) do
    # Blocking: fetch fresh data from strategy
    {:ok, _} = start_strategy_warmer(config)
    
    # Schedule periodic refresh
    schedule_periodic_refresh(config)
    
    {:noreply, config}
  end
  
  def handle_info(:start_strategy_warmer, config) do
    start_strategy_warmer(config)
    {:noreply, config}
  end
  
  def handle_info(:periodic_refresh, config) do
    start_strategy_warmer(config)
    schedule_periodic_refresh(config)
    {:noreply, config}
  end
end
```

### Warmer Implementations

#### File Warmer
```elixir
defmodule Lightning.Adaptors.CacheRestorer do
  @doc """
  Reads cache file and populates Cachex.
  Designed to be fast and non-blocking.
  """
  def start(config) do
    Task.start(fn ->
      case File.read(config.persist_path) do
        {:ok, binary} ->
          data = :erlang.binary_to_term(binary)
          populate_cache(config.cache, data)
          Logger.info("Cache restored from file")
        
        {:error, reason} ->
          Logger.warning("Failed to restore cache: #{inspect(reason)}")
      end
    end)
  end
  
  defp populate_cache(cache, data) do
    Enum.each(data, fn {key, value} ->
      Cachex.put(cache, key, value)
    end)
  end
end
```

#### Strategy Warmer
```elixir
defmodule Lightning.Adaptors.StrategyWarmer do
  @doc """
  Uses strategy to fetch fresh data and populate Cachex.
  Can be blocking or non-blocking depending on context.
  """
  def start(config, opts \\ []) do
    task_fn = fn ->
      case Lightning.Adaptors.Warmer.execute(config) do
        {:ok, pairs} ->
          populate_cache(config.cache, pairs)
          save_cache_file(config, pairs)
          Logger.info("Cache warmed from strategy")
        
        :ignore ->
          Logger.warning("Strategy warmer returned :ignore")
      end
    end
    
    if Keyword.get(opts, :blocking, false) do
      Task.await(Task.async(task_fn))
    else
      Task.start(task_fn)
    end
  end
  
  defp save_cache_file(config, pairs) do
    if config.persist_path do
      data = :erlang.term_to_binary(pairs)
      File.write(config.persist_path, data)
    end
  end
end
```

### Simplified Supervisor

```elixir
defmodule Lightning.Adaptors.Supervisor do
  use Supervisor
  
  def init(config) do
    children = [
      # CacheManager now owns and manages Cachex
      {Lightning.Adaptors.CacheManager, config}
    ]
    
    Supervisor.init(children, strategy: :one_for_one)
  end
  
  def start_link(opts) do
    name = Keyword.get(opts, :name, Lightning.Adaptors)
    cache_name = :"adaptors_cache_#{name}"
    
    config = %{
      name: name,
      cache: cache_name,
      strategy: Keyword.get(opts, :strategy),
      persist_path: Keyword.get(opts, :persist_path),
      warm_interval: Keyword.get(opts, :warm_interval, :timer.minutes(5))
    }
    
    Supervisor.start_link(__MODULE__, config,
      name: Lightning.Adaptors.Registry.via(name, nil, config)
    )
  end
end
```

## Implementation Benefits

### 1. Simplified Process Tree
- **Before**: Complex coordination between 3 processes
- **After**: CacheManager owns and manages everything

### 2. Clearer Startup Flow
- **Before**: 4 complex scenarios with race conditions
- **After**: 2 simple scenarios with `handle_continue`

### 3. Better Control
- **Before**: Supervisor guesses when to enable warmers
- **After**: CacheManager controls warmer lifecycle precisely

### 4. Easier Testing
- **Before**: Complex setup with multiple coordinating processes
- **After**: Test CacheManager in isolation

### 5. Cleaner Configuration
- **Before**: Multiple places to configure cache behavior
- **After**: Single configuration point in CacheManager

## Migration Strategy

### Phase 1: Implement New Architecture
1. Create new `CacheManager` that owns Cachex
2. Implement `CacheRestorer` and `StrategyWarmer` modules
3. Update `Supervisor` to only start CacheManager
4. Add comprehensive tests

### Phase 2: Replace Current Implementation
1. Update references to new architecture
2. Remove old complex startup logic
3. Update documentation

### Phase 3: Cleanup
1. Remove unused code
2. Simplify configuration options
3. Performance validation

## Success Criteria

### Functional Success
- ✅ Cache file exists → Non-blocking startup with file restore
- ✅ No cache file → Blocking startup with strategy fetch
- ✅ Periodic refresh continues to work
- ✅ All existing API functionality preserved

### Performance Success
- ✅ Startup time improved when cache file exists
- ✅ Memory usage unchanged
- ✅ No regression in cache hit rates

### Code Quality Success
- ✅ Reduced complexity in supervisor setup
- ✅ Easier to understand startup flow
- ✅ Better separation of concerns
- ✅ Improved testability

## Configuration

### Before (Complex)
```elixir
# Multiple configuration points
config = %{
  name: name,
  cache: cache_name,
  strategy: strategy,
  persist_path: path,
  offline_mode: boolean,    # Removed
  warm_interval: interval
}

# Complex supervisor logic
warmers = if enable_cachex_warmer?(config) do
  [warmer(state: config, module: Lightning.Adaptors.Warmer)]
else
  []
end
```

### After (Simple)
```elixir
# Single configuration point
config = %{
  name: name,
  cache: cache_name,
  strategy: strategy,
  persist_path: path,
  warm_interval: interval
}

# Simple supervisor - just start CacheManager
children = [{Lightning.Adaptors.CacheManager, config}]
```

## Risk Analysis

### Low Risk
- **Architecture Change**: Well-contained within adaptors system
- **API Compatibility**: No changes to public API
- **Process Management**: Simpler, not more complex

### Mitigation
- **Comprehensive Testing**: Test both cache file scenarios
- **Gradual Rollout**: Feature flag for new vs old architecture
- **Performance Monitoring**: Ensure no regressions

## Conclusion

This architectural simplification eliminates the complex coordination between Supervisor, CacheManager, and Cachex by having CacheManager own and manage Cachex internally. The result is:

1. **Simpler code** - Clear ownership and control flow
2. **Better performance** - Eliminated race conditions and coordination overhead
3. **Easier maintenance** - Single place to understand cache lifecycle
4. **Cleaner design** - Proper separation of concerns

The use of `handle_continue` for staged initialization is a perfect fit for this use case, allowing non-blocking startup when cache files exist while maintaining the ability to block when fresh data is required. 