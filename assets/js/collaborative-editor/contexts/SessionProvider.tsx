/**
 * SessionProvider - Handles shared Yjs document, awareness, and Phoenix Channel concerns
 * Provides common infrastructure for TodoStore and WorkflowStore
 */

import type React from "react";
import {
  createContext,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react";
import { PhoenixChannelProvider } from "y-phoenix-channel";
import * as awarenessProtocol from "y-protocols/awareness";
import { Doc as YDoc, encodeStateVector, createDocFromSnapshot } from "yjs";

import { useSocket } from "../../react/contexts/SocketProvider";
import type { AdaptorStoreInstance } from "../stores/createAdaptorStore";
import { createAdaptorStore } from "../stores/createAdaptorStore";
import {
  type AwarenessStoreInstance,
  createAwarenessStore,
} from "../stores/createAwarenessStore";
import {
  type CredentialStoreInstance,
  createCredentialStore,
} from "../stores/createCredentialStore";

export interface SessionContextValue {
  // Yjs infrastructure
  ydoc: YDoc | null;

  // Connection state
  isConnected: boolean;
  isSynced: boolean;

  // Store instances
  adaptorStore: AdaptorStoreInstance;
  credentialStore: CredentialStoreInstance;
  awarenessStore: AwarenessStoreInstance;
}

const SessionContext = createContext<SessionContextValue | null>(null);

export const useSession = () => {
  const context = useContext(SessionContext);
  if (!context) {
    throw new Error("useSession must be used within a SessionProvider");
  }
  return context;
};

function uint8ArrayToBase64(uint8Array: Uint8Array): string {
  const binaryString = Array.from(uint8Array, byte =>
    String.fromCharCode(byte)
  ).join("");
  return btoa(binaryString);
}

const waitForYDocSettled = (
  channelProvider: PhoenixChannelProvider,
  ydoc: YDoc
) => {
  const controller = new AbortController();

  const channelSyncedPromise = new Promise<void>((resolve, reject) => {
    const cleanup = () => {
      channelProvider.off("sync", handler);
    };

    const handler = (synced: boolean) => {
      if (synced) {
        cleanup();
        resolve();
      }
    };

    controller.signal.addEventListener("abort", () => {
      cleanup();
      reject(new Error("Aborted"));
    });
    channelProvider.on("sync", handler);
  });

  const firstUpdatePromise = new Promise<void>((resolve, reject) => {
    const cleanup = () => {
      ydoc.off("update", handler);
    };

    const handler = (_update: Uint8Array, origin: unknown) => {
      if (origin === channelProvider) {
        cleanup();
        resolve();
      }
    };

    controller.signal.addEventListener("abort", () => {
      cleanup();
      reject(new Error("Aborted"));
    });

    ydoc.on("update", handler);
  });

  return {
    abort: () => controller.abort(),
    fufilled: Promise.all([channelSyncedPromise, firstUpdatePromise]),
  };
};

interface SessionProviderProps {
  workflowId: string;
  userId: string;
  userName: string;
  children: React.ReactNode;
}

export const SessionProvider: React.FC<SessionProviderProps> = ({
  workflowId,
  userId,
  userName,
  children,
}) => {
  const { socket, isConnected } = useSocket();

  // Yjs state
  const [ydoc, setYdoc] = useState<YDoc | null>(null);
  const [provider, setProvider] = useState<PhoenixChannelProvider | null>(null);
  const [vectorOnJoin, setVectorOnJoin] = useState<string | null>(null);

  // useEffect(() => {
  //   if (!snapshot || !ydoc) return;

  //   const restoredDoc = createDocFromSnapshot(ydoc, snapshot);
  //   restoredDoc.getMap("workflow");
  //   console.log("restoredDoc", restoredDoc.toJSON());

  //   if (prevSnapshotRef.current === null) {
  //     prevSnapshotRef.current = snapshot;
  //     return;
  //   }

  //   console.log(
  //     "equalSnapshots",
  //     Y.equalSnapshots(prevSnapshotRef.current, snapshot)
  //   );

  //   prevSnapshotRef.current = snapshot;

  //   return () => {};
  // }, [snapshot, ydoc]);

  // React state
  const [isProviderConnected, setIsProviderConnected] = useState(false);
  const [isSynced, setIsSynced] = useState(false);

  // Store instances - created once and reused
  const adaptorStoreRef = useRef<AdaptorStoreInstance>(createAdaptorStore());

  const credentialStoreRef = useRef<CredentialStoreInstance>(
    createCredentialStore()
  );
  const awarenessStoreRef = useRef<AwarenessStoreInstance>(
    createAwarenessStore()
  );

  useEffect(() => {
    if (!ydoc || !provider) return;
    const { abort, fufilled } = waitForYDocSettled(provider, ydoc);

    void fufilled.then(() => {
      setVectorOnJoin(uint8ArrayToBase64(encodeStateVector(ydoc)));

      return;
    });

    return () => {
      abort();
    };
  }, [ydoc, provider]);

  // Initialize Yjs when socket is connected
  useEffect(() => {
    if (!isConnected || !socket) {
      return;
    }

    console.log("🚀 Initializing Session with PhoenixChannelProvider");

    // Create Yjs document and awareness
    const ydoc = new YDoc();
    const awarenessInstance = new awarenessProtocol.Awareness(ydoc);

    // Set up user data for awareness
    const userData = {
      id: userId,
      name: userName,
      color: generateUserColor(userId),
    };

    // Initialize awareness store with the awareness instance
    awarenessStoreRef.current.initializeAwareness(awarenessInstance, userData);

    // Create the Yjs channel provider
    const roomname = `workflow:collaborate:${workflowId}`;
    console.log("🔗 Creating PhoenixChannelProvider with:", {
      roomname,
      socketConnected: socket.isConnected(),
    });

    const channelProvider = new PhoenixChannelProvider(socket, roomname, ydoc, {
      awareness: awarenessInstance,
      connect: true,
    });

    // IDEA: We could have two different states here, one for just the user
    // information, that is uniqued (in case they have more than one session)
    // and one for the cursor information.

    // Provider event handlers
    const statusHandler = (...args: unknown[]) => {
      console.debug("PhoenixChannelProvider: status event", args);
      if (args.length > 0 && Array.isArray(args[0])) {
        const statusEvents = args[0];
        if (
          statusEvents[0] &&
          typeof statusEvents[0] === "object" &&
          "status" in statusEvents[0]
        ) {
          const status = (statusEvents[0] as { status: string }).status;
          console.debug(
            "PhoenixChannelProvider: setIsProviderConnected",
            status
          );
          setIsProviderConnected(status === "connected");
        }
      }
    };

    const syncHandler = (synced: boolean) => {
      console.debug("PhoenixChannelProvider: synced event", synced);
      setIsSynced(synced);
    };

    // Listen to provider status
    channelProvider.on("status", statusHandler);
    channelProvider.on("sync", syncHandler);

    // Also log initial provider state
    console.debug("PhoenixChannelProvider: initial state", {
      roomname,
      shouldConnect: channelProvider.shouldConnect,
      channel: channelProvider.channel,
      synced: channelProvider.synced,
      socketConnected: socket.isConnected(),
    });

    // Testing helper to simulate a reconnect
    window.triggerSessionReconnect = (timeout = 1000) => {
      socket.disconnect(
        () => {
          console.log("socket disconnected");
          setTimeout(() => {
            socket.connect();
            console.log("socket connected");
          }, timeout);
        },
        undefined,
        "Testing reconnect"
      );
    };

    let cleanupAdaptorChannel: (() => void) | undefined;
    let cleanupCredentialChannel: (() => void) | undefined;

    // Listen directly to channel for 'joined' state detection
    const cleanupJoinListener = setupJoinListener(
      channelProvider,
      isConnected => {
        setIsProviderConnected(isConnected);

        // Request adaptors when channel is successfully joined
        if (isConnected && adaptorStoreRef.current) {
          console.debug("Channel joined, requesting adaptors and credentials");

          cleanupAdaptorChannel =
            adaptorStoreRef.current._internal.connectChannel(channelProvider);

          cleanupCredentialChannel =
            credentialStoreRef.current._connectChannel(channelProvider);
        }
      }
    );

    // Store state
    setYdoc(ydoc);
    setProvider(channelProvider);

    // Set up automatic last seen updates via awareness store
    const cleanupLastSeenTimer =
      awarenessStoreRef.current._internal.setupLastSeenTimer();

    // Cleanup function
    return () => {
      console.debug("PhoenixChannelProvider: cleaning up");

      cleanupJoinListener();
      cleanupLastSeenTimer();
      cleanupAdaptorChannel?.();
      cleanupCredentialChannel?.();

      channelProvider.off("status", statusHandler);
      channelProvider.off("sync", syncHandler);

      // Clean up awareness store
      awarenessStoreRef.current.destroyAwareness();

      channelProvider.destroy();
      ydoc.destroy();
      setYdoc(null);
      setProvider(null);
      setIsProviderConnected(false);
      setIsSynced(false);
    };
  }, [isConnected, socket, workflowId, userId, userName]);

  // Context value with improved referential stability
  // awareness and users are now served by dedicated hooks for better performance
  const value = useMemo<SessionContextValue>(
    () => ({
      ydoc,
      isConnected: isProviderConnected,
      isSynced,
      adaptorStore: adaptorStoreRef.current,
      credentialStore: credentialStoreRef.current,
      awarenessStore: awarenessStoreRef.current,
    }),
    [ydoc, isProviderConnected, isSynced]
  );

  return (
    <SessionContext.Provider value={value}>{children}</SessionContext.Provider>
  );
};

// Helper functions
function generateUserColor(userId: string): string {
  const colors = [
    "#FF6B6B",
    "#4ECDC4",
    "#45B7D1",
    "#FFA07A",
    "#98D8C8",
    "#FFCF56",
    "#FF8B94",
    "#AED581",
  ];

  const hash = userId.split("").reduce((a, b) => {
    a = (a << 5) - a + b.charCodeAt(0);
    return a & a;
  }, 0);

  return colors[Math.abs(hash) % colors.length] || "#999999";
}

function setupJoinListener(
  channelProvider: PhoenixChannelProvider,
  callback: (isConnected: boolean) => void
) {
  const onJoinReceived = () => {
    if (channelProvider.channel?.state === "joined") {
      callback(true);
    }
  };
  channelProvider.channel?.joinPush.receive("ok", onJoinReceived);

  return () => {
    const hooks = channelProvider.channel?.joinPush.recHooks as
      | Array<{ callback: () => void }>
      | undefined;
    const hook = hooks?.find(hook => hook.callback === onJoinReceived);
    if (hook && hooks) {
      hooks.splice(hooks.indexOf(hook), 1);
    }
  };
}
