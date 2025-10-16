# Toast Notifications - Collaborative Editor

This guideline covers how to use toast notifications in the collaborative workflow editor.

## Overview

The collaborative editor uses [Sonner](https://sonner.emilkowal.ski/) via shadcn/ui for toast notifications. Toasts provide immediate user feedback for operations like saving, errors, and validations.

## Architecture

**Components**:
- `Toaster` - Wrapper component mounted at root (`assets/js/collaborative-editor/components/ui/Toaster.tsx`)
- `notifications` - Service API for triggering toasts (`assets/js/collaborative-editor/lib/notifications.ts`)

**Provider Location**:
```typescript
<SocketProvider>
  <SessionProvider>
    <StoreProvider>
      <Toaster />  {/* Mounted here */}
      {/* Rest of app */}
    </StoreProvider>
  </SessionProvider>
</SocketProvider>
```

## Usage

### Import the notification service:
```typescript
import { notifications } from "../lib/notifications";
```

### Info Notifications (Blue, 2s duration)
Use for successful operations and general information:

```typescript
notifications.info({
  title: "Workflow saved",
  description: "All changes have been synced"
});
```

### Alert Notifications (Red, 4s duration)
Use for errors and warnings that need attention:

```typescript
notifications.alert({
  title: "Failed to save workflow",
  description: "Please check your connection and try again"
});
```

### With Action Button
Add retry or other actions:

```typescript
notifications.alert({
  title: "Validation error",
  description: "Job name cannot be empty",
  action: {
    label: "Fix",
    onClick: () => {
      // Handle action
    }
  }
});
```

### Success Notifications (Green, 2s duration)
Explicit success confirmation:

```typescript
notifications.success({
  title: "Workflow published",
  description: "Your workflow is now live"
});
```

### Warning Notifications (Amber, 3s duration)
Non-critical warnings:

```typescript
notifications.warning({
  title: "Connection unstable",
  description: "Your changes may not sync immediately"
});
```

### Programmatic Dismissal
```typescript
// Dismiss specific toast
const toastId = notifications.info({ title: "Processing..." });
notifications.dismiss(toastId);

// Dismiss all toasts
notifications.dismiss();
```

## Styling Conventions

**Color Scheme**:
- **Info**: Blue (`border-blue-500`, `bg-blue-50`) - Matches Lightning's info flash
- **Alert**: Red (`border-red-500`, `bg-red-50`) - Matches Lightning's error flash
- **Success**: Green (`border-green-500`, `bg-green-50`)
- **Warning**: Amber (`border-amber-500`, `bg-amber-50`)

**Duration**:
- Info/Success: 2 seconds (quick confirmation)
- Warning: 3 seconds (middle ground)
- Alert: 4 seconds (needs more attention)
- Override: Pass `duration` option for custom timing

**Layout**:
- Position: Bottom-right of viewport
- Stacking: Up to 3 visible toasts
- Border: 4px left accent (matches Lightning alert components)

## Built-in Features

### Auto-dismiss with Hover-to-Pause
Toasts automatically dismiss after their duration, but hovering pauses the timer:
- Hover over toast → timer pauses
- Move away → timer resumes
- No configuration needed (built-in to Sonner)

### Manual Dismiss
All toasts have a close button (X) for immediate dismissal.

### Accessibility
- Keyboard navigation (Tab to focus, Enter to dismiss)
- ARIA labels (screen reader friendly)
- Alt+T hotkey to focus toasts

## Best Practices

### When to Use Toasts

**DO use toasts for**:
- ✅ Confirming user actions (save, delete, publish)
- ✅ Reporting errors that need immediate attention
- ✅ Providing actionable feedback (with retry button)
- ✅ Temporary status updates

**DON'T use toasts for**:
- ❌ Persistent state (use UI indicators instead)
- ❌ Form validation errors (use inline validation)
- ❌ Information that requires user acknowledgment (use modals)
- ❌ Multiple rapid operations (debounce or consolidate)

### Message Guidelines

**Titles**: Short, clear, action-focused
- Good: "Workflow saved", "Failed to connect"
- Bad: "Success", "Error occurred"

**Descriptions**: Brief context or next steps
- Good: "All changes have been synced"
- Bad: "The workflow has been successfully saved to the database and all users have been notified"

**Actions**: Clear, verb-based labels
- Good: "Retry", "Undo", "View Details"
- Bad: "OK", "Click here", "More"

### Error Handling Pattern

```typescript
try {
  const result = await riskyOperation();

  notifications.info({
    title: "Operation completed",
    description: `Processed ${result.count} items`
  });

  return result;
} catch (error) {
  notifications.alert({
    title: "Operation failed",
    description: error instanceof Error ? error.message : "Unknown error",
    action: {
      label: "Retry",
      onClick: () => riskyOperation()
    }
  });

  throw error; // Re-throw for upstream handling
}
```

## Testing

### Unit Testing
Mock Sonner in tests:

```typescript
import { vi } from "vitest";
import { toast } from "sonner";

vi.mock("sonner", () => ({
  toast: {
    info: vi.fn(),
    error: vi.fn(),
    success: vi.fn(),
    warning: vi.fn(),
    dismiss: vi.fn(),
  },
}));

// Test notification calls
notifications.info({ title: "Test" });
expect(toast.info).toHaveBeenCalledWith("Test", expect.objectContaining({
  classNames: expect.objectContaining({
    toast: expect.stringContaining("border-blue-500")
  })
}));
```

### Manual Testing
Use browser console to test:

```javascript
import('/js/collaborative-editor/lib/notifications.js')
  .then(({ notifications }) => {
    notifications.info({ title: 'Test', description: 'Testing notification' });
  });
```

## Migration from Other Notification Systems

**Phoenix Flash Messages** (LiveView):
- Phoenix flash remains for server-side page transitions
- React toasts for client-side collaborative editor operations
- Both systems coexist without interference

**Console Logging**:
- Keep existing console.log statements
- Toasts complement logging, don't replace it
- Logs for debugging, toasts for user feedback

## References

- Original requirements: `.context/stuart/analysis/toast-notifications-requirements.md`
- Implementation plan: `.context/shared/plans/2025-10-08-toast-notifications.md`
- Sonner documentation: https://sonner.emilkowal.ski/
- shadcn/ui Sonner: https://ui.shadcn.com/docs/components/sonner
