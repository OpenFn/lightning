# Mini History Component

A compact, stripped-down version of the history table designed to fit in smaller spaces while maintaining core functionality.

## Features

- ✅ **Compact Design**: Fits in sidebars and smaller containers with a fixed max-height of 384px (24rem)
- ✅ **Expandable Work Orders**: Click to expand and see runs within each work order
- ✅ **Clickable Runs**: When you click on a run, it sends a `{:run_selected, run_id}` message to the parent LiveView
- ✅ **Real-time Updates**: Parent LiveView can trigger refreshes when work orders/runs change
- ✅ **Status Pills**: Shows status for both work orders and runs with color-coded pills
- ✅ **Recent Activity**: Shows last 7 days of activity (configurable)
- ❌ **No Bulk Operations**: Removed checkboxes, bulk rerun, and export functionality
- ❌ **No Complex Filtering**: Simplified to show recent activity only
- ❌ **No Step Details**: Runs don't show individual steps (these are visualized elsewhere)
- ❌ **No Pagination**: Limited to 20 most recent items

## Usage

### As a Live Component

```elixir
<.live_component
  module={LightningWeb.RunLive.MiniIndex}
  id="mini-history"
  project={@project}
/>
```

### Handling Run Selection

In your parent LiveView, handle the run selection event:

```elixir
@impl true
def handle_info({:run_selected, run_id}, socket) do
  # Handle run selection - could navigate to run details,
  # load run data, update visualizations, etc.
  {:noreply, assign(socket, selected_run_id: run_id)}
end
```

### Real-time Updates

Since LiveComponents can't subscribe to PubSub directly, the parent LiveView should handle subscriptions and trigger component refreshes:

```elixir
# In your parent LiveView's mount/3:
def mount(_params, _session, %{assigns: %{project: project}} = socket) do
  WorkOrders.subscribe(project.id)
  # ... rest of mount
end

# Handle work order events and refresh the component:
def handle_info(%Lightning.WorkOrders.Events.WorkOrderCreated{}, socket) do
  send_update(LightningWeb.RunLive.MiniIndex, id: "mini-history", action: :refresh)
  {:noreply, socket}
end

def handle_info(%Lightning.WorkOrders.Events.WorkOrderUpdated{}, socket) do
  send_update(LightningWeb.RunLive.MiniIndex, id: "mini-history", action: :refresh)
  {:noreply, socket}
end

def handle_info(%mod{}, socket) 
    when mod in [Lightning.WorkOrders.Events.RunCreated, Lightning.WorkOrders.Events.RunUpdated] do
  send_update(LightningWeb.RunLive.MiniIndex, id: "mini-history", action: :refresh)
  {:noreply, socket}
end
```

### Example Integration

See `lib/lightning_web/live/run_live/example_mini_usage.ex` for a complete example of integrating the mini history into a dashboard layout.

## File Structure

- `mini_index.ex` - Main LiveComponent
- `mini_index.html.heex` - Template with compact styling
- `example_mini_usage.ex` - Example usage in a dashboard layout

## Styling

The component uses:
- Tailwind CSS for responsive design
- Fixed height with scrolling (`max-h-96 overflow-y-auto`)
- Clean borders and subtle shadows
- Hover states for interactive elements
- Color-coded status pills from the existing component library

## Customization

### Changing the Time Range

Modify the `perform_search/1` function in `mini_index.ex`:

```elixir
search_params = %{
  "date_after" => Timex.now() |> Timex.shift(days: -14) |> DateTime.to_string() # Last 14 days
}
```

### Changing the Item Limit

Modify the page size in `perform_search/1`:

```elixir
Invocation.search_workorders(
  project,
  search_params,
  %{"page_size" => "50"} # Show 50 items instead of 20
)
```

### Adding Filters

You can add minimal filtering by modifying the `search_params` map in `perform_search/1`:

```elixir
search_params = %{
  "date_after" => Timex.now() |> Timex.shift(days: -7) |> DateTime.to_string(),
  "workflow_id" => specific_workflow_id, # Filter to specific workflow
  "success" => "true" # Only successful runs
}
```

### Manual Refresh

The component also supports manual refresh via an event:

```elixir
# Trigger refresh from parent or from within the component
send_update(LightningWeb.RunLive.MiniIndex, id: "mini-history", action: :refresh)
```

## Integration Tips

1. **Sidebar Usage**: Perfect for workflow editor sidebars or dashboard panels
2. **Run Visualization**: Use the `{:run_selected, run_id}` message to trigger detailed visualizations
3. **Responsive Design**: Component adapts to container width
4. **State Management**: Parent LiveView can track selected runs and update other UI accordingly
5. **Real-time Updates**: Parent handles PubSub subscriptions and triggers component refreshes

## Performance Notes

- Only loads last 20 work orders by default
- Uses async loading with loading states
- Real-time updates are handled by parent LiveView for better performance
- No heavy operations like bulk processing or complex filtering
- Component refreshes are lightweight and only reload the data list 