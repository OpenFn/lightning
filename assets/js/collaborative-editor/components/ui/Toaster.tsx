import { Toaster as Sonner } from "sonner";

type ToasterProps = React.ComponentProps<typeof Sonner>;

/**
 * Toast notification provider using Sonner
 *
 * Provides toast notifications for the collaborative editor with
 * Lightning's design system. Toasts auto-dismiss after 2-4 seconds
 * (depending on type) unless user hovers over them.
 *
 * Features:
 * - Auto-dismiss with hover-to-pause
 * - Stackable notifications (up to 3 visible)
 * - Manual dismiss via close button
 * - Accessible (keyboard navigation, ARIA labels)
 *
 * This component should be mounted once at the root of the
 * collaborative editor.
 *
 * Usage:
 * ```tsx
 * import { Toaster } from "./components/ui/Toaster";
 *
 * function App() {
 *   return (
 *     <>
 *       <Toaster />
 *       {/* Your app components *\/}
 *     </>
 *   );
 * }
 * ```
 */
export function Toaster(props: ToasterProps) {
  return (
    <Sonner
      position="bottom-right"
      expand={false}
      visibleToasts={3}
      closeButton={true}
      duration={2000}
      className="toaster group"
      toastOptions={{
        classNames: {
          toast:
            "group toast bg-white border border-slate-200 shadow-lg " +
            "rounded-lg",
          description: "text-slate-600 text-sm",
          actionButton:
            "bg-primary-600 text-white px-3 py-1.5 rounded " +
            "hover:bg-primary-700",
          cancelButton:
            "bg-slate-100 text-slate-700 px-3 py-1.5 rounded " +
            "hover:bg-slate-200",
          closeButton: "border border-slate-200 hover:border-slate-300",
        },
      }}
      {...props}
    />
  );
}
