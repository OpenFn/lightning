/**
 * useVersionSelect Hook
 *
 * Provides a consolidated handler for workflow version selection.
 * When switching back to "latest" from a snapshot, clears IndexedDB cache
 * to ensure fresh data is loaded from the server.
 *
 * This hook replaces duplicated handleVersionSelect functions across:
 * - CollaborativeEditor.tsx
 * - components/ide/IDEHeader.tsx
 */

import _logger from "#/utils/logger";
import { useURLState } from "#/react/lib/use-url-state";
import { useWorkflowState } from "./useWorkflow";

const logger = _logger.ns("useVersionSelect").seal();

/**
 * Clears Y.Doc IndexedDB cache for a specific workflow
 * This forces a fresh sync from the server when reconnecting
 */
async function clearYDocIndexedDB(workflowId: string): Promise<void> {
  try {
    logger.log("🗑️  Starting IndexedDB clear for workflow:", workflowId);

    // Get all IndexedDB databases
    const databases = await indexedDB.databases();
    logger.log(
      "📦 Found IndexedDB databases:",
      databases.map(db => db.name)
    );

    // Find Y.Doc databases for this workflow
    // y-indexeddb typically creates databases with names like:
    // - "y-indexeddb-workflow:collaborate:{id}"
    // - Or just the room name itself
    const roomName = `workflow:collaborate:${workflowId}`;
    const dbNamesToDelete = databases
      .filter(db => {
        const name = db.name || "";
        const matches =
          name.includes(workflowId) ||
          name.includes(roomName) ||
          name.includes("y-indexeddb");
        if (matches) {
          logger.log("  ✓ Will delete:", name);
        }
        return matches;
      })
      .map(db => db.name!);

    if (dbNamesToDelete.length === 0) {
      logger.warn("⚠️  No Y.Doc IndexedDB databases found to clear!");
      logger.log("Expected to find databases containing:", {
        workflowId,
        roomName,
        pattern: "y-indexeddb",
      });
      return;
    }

    logger.log(
      `🗑️  Deleting ${dbNamesToDelete.length} IndexedDB database(s)...`
    );

    // Delete each database
    const results = await Promise.allSettled(
      dbNamesToDelete.map(async dbName => {
        logger.log("  Deleting:", dbName);
        await new Promise<void>((resolve, reject) => {
          const request = indexedDB.deleteDatabase(dbName);
          request.onsuccess = () => {
            logger.log("  ✓ Deleted:", dbName);
            resolve();
          };
          request.onerror = () => {
            logger.error("  ✗ Failed to delete:", dbName, request.error);
            reject(request.error);
          };
          request.onblocked = () => {
            logger.warn(
              "  ⏸  Deletion blocked (connections still open):",
              dbName
            );
            // Resolve anyway - deletion will complete when unblocked
            resolve();
          };
        });
      })
    );

    const succeeded = results.filter(r => r.status === "fulfilled").length;
    const failed = results.filter(r => r.status === "rejected").length;

    logger.log(
      `✅ IndexedDB clear complete: ${succeeded} succeeded, ${failed} failed`
    );
  } catch (error) {
    logger.error("❌ Failed to clear IndexedDB:", error);
    // Don't throw - IndexedDB clearing is a best-effort optimization
    // If it fails, Y.Doc will still sync (just might use stale cache initially)
  }
}

/**
 * Hook that provides a version selection handler.
 * When switching to "latest", clears IndexedDB to force fresh sync.
 *
 * @returns Handler function for version selection
 */
export function useVersionSelect() {
  const { updateSearchParams } = useURLState();
  const workflowId = useWorkflowState(state => state.workflow?.id);

  const handleVersionSelect = async (version: number | "latest") => {
    logger.log("Version switch initiated", {
      to: version === "latest" ? "latest" : `v${version}`,
    });

    // When switching to "latest", clear IndexedDB cache first
    // This prevents loading stale data from cache when returning from a snapshot
    if (version === "latest" && workflowId) {
      await clearYDocIndexedDB(workflowId);

      // Wait a bit for IndexedDB deletion to fully complete
      // This ensures deletion finishes before new Y.Doc connects
      await new Promise(resolve => setTimeout(resolve, 100));

      logger.log("✓ IndexedDB clear complete, proceeding with version switch");
    }

    // Update URL parameter to trigger version switch
    if (version === "latest") {
      updateSearchParams({ v: null }); // Remove version param
    } else {
      updateSearchParams({ v: String(version) }); // Set version param
    }
  };

  return handleVersionSelect;
}
