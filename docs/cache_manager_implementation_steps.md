# Cache Manager Simplification - Implementation Steps

## Overview

### Current State
The Lightning Adaptors system currently has a complex architecture with difficult-to-follow coordination between three separate processes:
- **Supervisor** - Decides when to enable Cachex warmers and starts both Cachex and CacheManager
- **CacheManager** - A GenServer that handles 4 different startup scenarios with complex offline mode logic
- **Cachex** - Started by Supervisor with optional warmers, but CacheManager tries to coordinate with it

This creates race conditions, complex startup logic, and makes the system hard to understand and maintain.

### What We're Achieving
Transform this into a **simple, clean architecture** where:
- **CacheManager becomes a Supervisor** that owns and manages Cachex internally
- **Two specialized Cachex warmers** handle cache restoration and strategy fetching
- **Eliminate offline mode complexity** - it's an underused feature that adds significant complexity
- **Simplify startup to 2 scenarios**: cache file exists (fast startup) or doesn't (blocks until ready)

### Benefits
- **Cleaner process ownership**: CacheManager owns Cachex, no external coordination needed
- **Faster startup**: When cache file exists, app starts immediately and cache is restored async
- **Easier to understand**: Clear, linear flow instead of complex scenario handling
- **Better reliability**: Leverages Cachex's built-in warmer system instead of custom coordination
- **Reduced complexity**: Removes 200+ lines of complex scenario handling code

### Architecture Transformation
```
BEFORE:  Supervisor → CacheManager (GenServer) + Cachex (separate processes)
AFTER:   Supervisor → CacheManager (Supervisor) → Cachex (child process)
```

The key insight is that CacheManager should **own** Cachex rather than try to coordinate with it as a sibling process.

---

## Step 1: Create CacheRestorer Module

**Objective**: Create a Cachex warmer that restores cache from disk file.

**What to do**:
- Create new module `Lightning.Adaptors.CacheRestorer` 
- Implement `Cachex.Warmer` behaviour with single `execute/1` callback
- Read binary file from `config.persist_path`
- Deserialize with `:erlang.binary_to_term/1`
- Return `{:ok, pairs}` on success or `:ignore` on failure
- Add warning log on failure to read file

**Verify**: Module compiles and `CacheRestorer.execute(%{persist_path: "test.bin"})` returns either `{:ok, pairs}` or `:ignore`.

---

## Step 2: Enhance StrategyWarmer Module  

**Objective**: Modify existing warmer to save cache to disk after successful fetch.

**What to do**:
- Open `Lightning.Adaptors.Warmer` (rename to `StrategyWarmer` for clarity)
- After successful strategy execution, save pairs to disk
- Use `:erlang.term_to_binary/1` to serialize pairs
- Write to `config.persist_path` if configured
- Keep existing warmer logic intact

**Verify**: After warmer executes successfully, cache file is created at persist_path location.

---

## Step 3: Convert CacheManager to Supervisor

**Objective**: Change CacheManager from GenServer to Supervisor that manages Cachex.

**What to do**:
- Change `use GenServer` to `use Supervisor`
- Replace `init/1` to return supervisor spec
- Remove all `handle_continue`, `handle_info`, and `handle_call` callbacks
- Create `determine_warmers/1` function that returns warmer list
- Start Cachex as only child with determined warmers

**Verify**: CacheManager starts successfully and Cachex process is running as its child.

---

## Step 4: Implement Warmer Selection Logic

**Objective**: Determine which warmers to use based on cache file existence.

**What to do**:
- In `determine_warmers/1`, check if cache file exists
- If file exists: return CacheRestorer (required) + StrategyWarmer (optional)
- If no file: return only StrategyWarmer (required)
- Use Cachex warmer spec format with module, state, and required flag
- Pass full config as warmer state

**Verify**: Different warmer configurations are returned based on cache file presence.

---

## Step 5: Simplify Supervisor Module

**Objective**: Remove complex warmer logic from Lightning.Adaptors.Supervisor.

**What to do**:
- Remove `enable_cachex_warmer?/1` function
- Remove warmer configuration logic from `init/1`
- Start only CacheManager as child (no direct Cachex startup)
- Keep config assembly logic but remove offline_mode handling
- Ensure CacheManager receives full config

**Verify**: Supervisor starts with only CacheManager child, no Cachex process at supervisor level.

---

## Step 6: Remove Offline Mode Configuration

**Objective**: Clean up configuration by removing unused offline mode.

**What to do**:
- Remove `offline_mode` from config assembly in Supervisor
- Remove `offline_mode` checks from CacheManager
- Remove offline-related scenarios from code
- Update config typespecs to exclude offline_mode
- Search for any remaining offline_mode references

**Verify**: No references to `offline_mode` remain in the codebase.

---

## Step 7: Clean Up Redundant Code

**Objective**: Remove complex scenario handling and redundant functions.

**What to do**:
- Delete `determine_scenario/1` function
- Delete `handle_scenario/2` and all scenario-specific handlers
- Remove async warming functions (now handled by Cachex)
- Remove manual scheduling code (Cachex handles this)
- Keep only essential helper functions

**Verify**: CacheManager module is under 100 lines of code.

---

## Step 8: Update Tests for CacheManager

**Objective**: Ensure tests reflect new supervisor-based architecture.

**What to do**:
- Update CacheManager tests to expect Supervisor behavior
- Test that Cachex starts as child process
- Test warmer selection logic with and without cache file
- Remove tests for offline scenarios
- Add tests for CacheRestorer and enhanced StrategyWarmer

**Verify**: All CacheManager tests pass with new architecture.

---

## Step 9: Integration Testing

**Objective**: Verify the complete system works end-to-end.

**What to do**:
- Test cold start (no cache file) - should block until strategy completes
- Test warm start (cache file exists) - should not block startup
- Test cache file creation after strategy fetch
- Test periodic refresh continues to work
- Verify no regression in API functionality

**Verify**: System starts correctly in both scenarios and cache operations work as expected.

---

## Step 10: Performance Validation

**Objective**: Ensure simplified architecture performs as well or better.

**What to do**:
- Measure startup time with cache file (should be faster)
- Measure memory usage (should be same or less)
- Check cache hit rates remain unchanged
- Verify no race conditions during startup
- Load test concurrent cache access during warming

**Verify**: Performance metrics meet or exceed current implementation.

---

## Final Checklist

- [x] CacheRestorer created and tested
- [x] StrategyWarmer saves cache to disk
- [x] CacheManager is now a Supervisor
- [x] Warmer selection logic works correctly
- [x] Supervisor simplified
- [ ] Offline mode completely removed
- [ ] Code significantly simplified
- [x] All tests updated and passing
- [x] Integration tests confirm both scenarios work
- [ ] Performance validated

## Success Criteria

The implementation is complete when:
1. Cache file exists → App starts immediately, cache restored from file
2. No cache file → Cache blocks access until strategy fetch completes  
3. Periodic refresh continues working
4. Code is simpler and easier to understand
5. No offline mode complexity remains 