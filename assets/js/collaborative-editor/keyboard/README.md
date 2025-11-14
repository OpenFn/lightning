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

## Installation

The system is already installed and ready to use. No additional dependencies
needed.

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
// In your application code (not the library):
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

## Migration Guide (Future)

When ready to migrate from react-hotkeys-hook:

1. **Define your priority constants** (in application code):

   ```typescript
   // constants/keyboard.ts (in your application)
   export const PRIORITY = {
     MODAL: 100,
     IDE: 50,
     RUN_PANEL: 25,
     PANEL: 10,
     DEFAULT: 0,
   };
   ```

2. **Replace useHotkeys with useKeyboardShortcut:**

   ```tsx
   // Before
   import { useHotkeys } from 'react-hotkeys-hook';
   import { HOTKEY_SCOPES } from './constants/hotkeys';

   useHotkeys('Escape', handleEscape, {
     scopes: [HOTKEY_SCOPES.PANEL],
     enableOnFormTags: true,
   });

   // After
   import { useKeyboardShortcut } from '#/collaborative-editor/keyboard';
   import { PRIORITY } from './constants/keyboard';

   useKeyboardShortcut('Escape', handleEscape, PRIORITY.PANEL);
   // enableOnFormTags is now always true by default
   ```

3. **Remove scope management:**

   ```tsx
   // Before
   const { enableScope, disableScope } = useHotkeysContext();
   useEffect(() => {
     enableScope(HOTKEY_SCOPES.MODAL);
     disableScope(HOTKEY_SCOPES.PANEL);
     return () => {
       disableScope(HOTKEY_SCOPES.MODAL);
       enableScope(HOTKEY_SCOPES.PANEL);
     };
   }, []);

   // After
   useKeyboardShortcut('Escape', handleEscape, PRIORITY.MODAL, {
     enabled: isModalOpen, // Component controls its own state
   });
   ```

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
- Try-catch around handlers (one bad handler doesn't break others)
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
