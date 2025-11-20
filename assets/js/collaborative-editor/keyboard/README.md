# Priority-Based Keyboard Shortcuts

A centralized keyboard handling system for the collaborative editor that
provides explicit priority-based handler selection, preventing conflicts and
simplifying keyboard logic.

## Features

- **Explicit priorities**: No more guessing which handler will fire
- **Return false pattern**: Handler can pass control to next handler
- **Smart defaults**: Always works in form fields, prevents default browser
  behavior
- **Efficient**: Only one tinykeys listener per key combo
- **Type-safe**: Full TypeScript support
- **Enable/disable**: Control handlers without unmounting

## Basic Usage

### 1. Wrap your app with KeyboardProvider

```tsx
import { KeyboardProvider } from '#/collaborative-editor/keyboard';

function CollaborativeEditor() {
  return <KeyboardProvider>{/* Your app components */}</KeyboardProvider>;
}
```

### 2. Register keyboard shortcuts in components

```tsx
import { useKeyboardShortcut } from '#/collaborative-editor/keyboard';

function Inspector() {
  const handleEscape = () => {
    closeInspector();
  };

  // Priority is just a number - higher numbers execute first
  useKeyboardShortcut('Escape', handleEscape, 10);

  return <div>Inspector content</div>;
}
```

## Priority System

Priority is just a number:

- **Higher number = higher priority** (executes first)
- **Same priority = most recently mounted component wins**
- **Disabled handlers are skipped**

**Suggested approach**: Define constants in your application:

```typescript
const PRIORITY = {
  MODAL: 100, // Highest priority
  IDE: 50, // Full-screen IDE
  RUN_PANEL: 25, // Manual run panel
  PANEL: 10, // Inspector panel
  DEFAULT: 0, // Base level
};

// Then use:
useKeyboardShortcut('Escape', handler, PRIORITY.MODAL);
```

## Advanced Patterns

### Return False to Pass Control

A handler can return `false` to pass the event to the next handler in priority
order:

```tsx
// FullScreenIDE.tsx (higher priority)
useKeyboardShortcut(
  'Escape',
  e => {
    if (monacoRef.current?.hasTextFocus()) {
      monacoRef.current.blur();
      return false; // Let Inspector's ESC handler run if it wants
    }
    closeEditor();
    // Implicit return undefined = we handled it
  },
  50
); // IDE priority

// Inspector.tsx (lower priority)
useKeyboardShortcut(
  'Escape',
  () => {
    closeInspector(); // Will run if IDE returns false
  },
  10
); // Panel priority
```

### Error Handling

**Errors stop the handler chain immediately and propagate to React:**

```tsx
useKeyboardShortcut(
  'Cmd+s',
  () => {
    if (!canSave) {
      throw new Error('Cannot save in current state');
    }
    saveDocument();
  },
  10
);
```

**Key behaviors:**

- Errors are logged to console with context (for debugging)
- Errors are re-thrown to React error boundaries and monitoring tools
- **Lower-priority handlers do NOT run** when an error is thrown
- Only `return false` triggers fallback to next handler
- Use errors for exceptional cases, `return false` for intentional pass-through

### Enable/Disable Without Unmounting

Control whether a handler is active using the `enabled` option:

```tsx
function FullScreenIDE({ isOpen }) {
  useKeyboardShortcut(
    'Escape',
    () => {
      onClose();
    },
    50,
    {
      // IDE priority
      enabled: isOpen, // Only respond when IDE is open
    }
  );
}
```

### Multiple Key Combos

Register multiple key combinations for the same handler:

```tsx
useKeyboardShortcut(
  'Cmd+Enter, Ctrl+Enter',
  () => {
    submitForm();
  },
  0
); // Default priority
```

### Customize Behavior

```tsx
useKeyboardShortcut(
  'Enter',
  () => {
    submitForm();
  },
  0,
  {
    // Default priority
    preventDefault: false, // Don't prevent default behavior
    stopPropagation: false, // Allow event to bubble
    enabled: canSubmit, // Conditional activation
  }
);
```

## Options Reference

```typescript
interface KeyboardHandlerOptions {
  /**
   * Prevent default browser behavior
   * @default true
   */
  preventDefault?: boolean;

  /**
   * Stop event propagation after handler executes
   * @default true
   */
  stopPropagation?: boolean;

  /**
   * Enable/disable handler without unmounting
   * @default true
   */
  enabled?: boolean;
}
```

## Key Combo Syntax

The system uses [tinykeys](https://github.com/jamiebuilds/tinykeys) for key
combo parsing. Common patterns:

- Single keys: `"Escape"`, `"Enter"`, `"a"`
- Modifiers: `"Cmd+s"`, `"Ctrl+Enter"`, `"Shift+Alt+k"`
- Multiple combos: `"Cmd+Enter, Ctrl+Enter"` (comma-separated)
- Case-insensitive: `"cmd+s"` and `"Cmd+S"` are equivalent

**Platform Modifiers:**

- `Cmd` = ⌘ on Mac, Windows key on Windows
- `Ctrl` = Control on all platforms
- `Shift` = Shift on all platforms
- `Alt` = Option on Mac, Alt on Windows

## Comparison with react-hotkeys-hook

| Feature              | react-hotkeys-hook       | Priority System                |
| -------------------- | ------------------------ | ------------------------------ |
| Priority control     | Scope-based (implicit)   | Number-based (explicit)        |
| Handler selection    | Last registered in scope | Highest priority + most recent |
| Enable/disable       | enabledScopes            | enabled option                 |
| Form fields          | enableOnFormTags option  | Always works                   |
| preventDefault       | Optional                 | Default true                   |
| stopPropagation      | Manual in callback       | Default true                   |
| Pass to next handler | Not possible             | Return false                   |

## Testing

Unit tests are in `KeyboardProvider.test.tsx`. Run with:

```bash
cd assets
npm test -- keyboard/KeyboardProvider.test.tsx
```

## Architecture

```
keyboard/
├── types.ts                    # TypeScript types and constants
├── KeyboardProvider.tsx        # Provider and hook implementation
├── KeyboardProvider.test.tsx   # Unit tests
├── index.ts                    # Public API exports
└── README.md                   # This file
```

**Key Design Decisions:**

- Single tinykeys listener per combo (efficient)
- Registry in ref (doesn't trigger re-renders)
- Stable callback refs (prevents unnecessary re-registration)
- Errors are logged and re-thrown (visible to error boundaries/monitoring)
- Default preventDefault/stopPropagation (matches existing behavior)

## Troubleshooting

**Handler not firing:**

- Check that component is mounted within KeyboardProvider
- Verify key combo syntax (use tinykeys syntax)
- Check if higher priority handler is claiming the event
- Verify enabled option is true

**Multiple handlers firing:**

- Check priorities - higher priority should block lower
- Verify handler isn't returning false accidentally
- Check stopPropagation option

**Handler firing in wrong order:**

- Higher number = higher priority
- Same priority = most recent wins
- Define your own priority constants for consistency
