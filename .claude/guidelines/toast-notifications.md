# Toast Notifications - Collaborative Editor

This guideline covers how to use toast notifications in the collaborative workflow editor.

## Overview

The collaborative editor uses [Sonner](https://sonner.emilkowal.ski/) **2.x**
(`^2.0.7` in `assets/package.json`) via shadcn/ui for toast notifications. Toasts provide
immediate user feedback for operations like saving, errors, and validations.

## Architecture

**Components**:
- `Toaster` - Wrapper component mounted at root (`assets/js/collaborative-editor/components/ui/Toaster.tsx`)
- `notifications` - Service API for triggering toasts (`assets/js/collaborative-editor/lib/notifications.ts`)

**Provider Location**:
```typescript
<KeyboardProvider>
  <SocketProvider>
    <SessionProvider>
      <StoreProvider>
        <LiveViewActionsProvider>
          <CredentialModalProvider>
            <MonacoRefProvider>
              <Toaster />  {/* Mounted here — CollaborativeEditor.tsx:275 */}
              {/* Rest of app */}
```

## Usage

### Import the notification service:
```typescript
import { notifications } from "../lib/notifications";
```

### Info Notifications (Blue, 3s duration)
Use for successful operations and general information:

```typescript
notifications.info({
  title: "Workflow saved",
  description: "All changes have been synced"
});
```

### Alert Notifications (Red, 6s duration)
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

### Success Notifications (Green, 3s duration)
Explicit success confirmation:

```typescript
notifications.success({
  title: "Workflow published",
  description: "Your workflow is now live"
});
```

### Warning Notifications (Amber, 6s duration)
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

**Color Scheme** (all classes carry Tailwind's `!` important prefix to override Sonner's
defaults — see `lib/notifications.ts`):
- **Info**: Blue (`!bg-blue-50`, `!border-l-4`, `!border-l-blue-500`)
- **Alert**: Red (`!bg-red-50`, `!border-l-4`, `!border-l-red-500`)
- **Success**: Green (`!bg-green-50`, `!border-l-4`, `!border-l-green-500`)
- **Warning**: Amber (`!bg-amber-50`, `!border-l-4`, `!border-l-amber-500`)

**Duration** (read the `duration:` literals in `notifications.ts`, not its JSDoc — the JSDoc
is stale):
- Info/Success: 3 seconds
- Alert/Warning: 6 seconds
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
  // Toaster.tsx imports this; without it any test that renders Toaster gets undefined.
  Toaster: () => null,
}));

// Test notification calls
notifications.info({ title: "Test" });
expect(toast.info).toHaveBeenCalledWith("Test", expect.objectContaining({
  classNames: expect.objectContaining({
    toast: expect.stringContaining("!border-l-blue-500")
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
