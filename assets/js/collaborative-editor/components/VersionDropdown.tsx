import { useEffect, useRef, useState } from "react";

import { channelRequest } from "../hooks/useChannel";
import { useSession } from "../hooks/useSession";

interface Version {
  lock_version: number;
  inserted_at: string;
  is_latest: boolean;
}

interface VersionDropdownProps {
  currentVersion: number | null;
  latestVersion: number | null;
  workflowId: string;
  projectId: string;
  onVersionSelect: (version: number | "latest") => void;
}

export function VersionDropdown({
  currentVersion,
  latestVersion,
  workflowId,
  projectId,
  onVersionSelect,
}: VersionDropdownProps) {
  const [isOpen, setIsOpen] = useState(false);
  const [versions, setVersions] = useState<Version[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const dropdownRef = useRef<HTMLDivElement>(null);
  const { provider } = useSession();
  const channel = provider?.channel;

  // Show placeholder while loading version information
  const isLoadingVersion = currentVersion === null || latestVersion === null;

  // Determine if viewing latest version (only when we have both values)
  const isLatestVersion = !isLoadingVersion && currentVersion === latestVersion;

  // Format version display
  const currentVersionDisplay = isLoadingVersion
    ? "•"
    : isLatestVersion
      ? "latest"
      : `v${String(currentVersion).substring(0, 7)}`;

  // Style based on version (matching snapshot_version_chip)
  const buttonStyles = isLoadingVersion
    ? "bg-gray-100 text-gray-600 hover:bg-gray-200"
    : isLatestVersion
      ? "bg-primary-100 text-primary-800 hover:bg-primary-200"
      : "bg-yellow-100 text-yellow-800 hover:bg-yellow-200";

  // Close dropdown when clicking outside or pressing Escape
  useEffect(() => {
    function handleClickOutside(event: MouseEvent) {
      if (
        dropdownRef.current &&
        !dropdownRef.current.contains(event.target as Node)
      ) {
        setIsOpen(false);
      }
    }

    function handleEscape(event: KeyboardEvent) {
      if (event.key === "Escape") {
        setIsOpen(false);
      }
    }

    if (isOpen) {
      // Use capture phase to catch events before they're stopped by React Flow
      document.addEventListener("mousedown", handleClickOutside, true);
      document.addEventListener("keydown", handleEscape);
      return () => {
        document.removeEventListener("mousedown", handleClickOutside, true);
        document.removeEventListener("keydown", handleEscape);
      };
    }
  }, [isOpen]);

  // Fetch versions when dropdown opens
  useEffect(() => {
    console.log("VersionDropdown effect:", {
      isOpen,
      versionsLength: versions.length,
      hasChannel: !!channel,
      channel,
    });

    if (isOpen && channel) {
      // Only fetch if we don't already have versions OR if we're not already loading
      if (versions.length === 0 && !isLoading) {
        console.log("Fetching versions from channel...");
        setIsLoading(true);
        setError(null);

        channelRequest<{ versions: Version[] }>(channel, "request_versions", {})
          .then(response => {
            console.log("Received versions response:", response);
            console.log("Versions array:", response.versions);
            console.log("Versions length:", response.versions?.length);
            setVersions(response.versions || []);
            setIsLoading(false);
          })
          .catch(err => {
            console.error("Failed to fetch versions:", err);
            setError("Failed to load versions");
            setIsLoading(false);
          });
      }
    }
  }, [isOpen, versions.length, channel, isLoading]);

  // Listen for workflow_saved broadcasts to update version list
  useEffect(() => {
    if (!channel) return;

    const handleWorkflowSaved = (payload: unknown) => {
      console.log("workflow_saved broadcast received:", payload);
      console.log("Current versions before clear:", versions);

      // Clear the versions list to force refetch on next dropdown open
      // This prevents duplicates and ensures fresh data
      setVersions([]);
      console.log("Cleared version list after workflow save");
    };

    channel.on("workflow_saved", handleWorkflowSaved);

    return () => {
      channel.off("workflow_saved", handleWorkflowSaved);
    };
  }, [channel, versions]);

  const handleVersionClick = (version: Version) => {
    if (version.is_latest) {
      onVersionSelect("latest");
    } else {
      onVersionSelect(version.lock_version);
    }
    setIsOpen(false);
  };

  return (
    <div ref={dropdownRef} className="relative inline-block">
      <button
        type="button"
        onClick={() => setIsOpen(!isOpen)}
        className={`inline-flex items-center gap-1 rounded-md px-1.5 py-0.5 text-xs font-medium transition-colors ${buttonStyles}`}
        aria-expanded={isOpen}
        aria-haspopup="true"
      >
        <span>{currentVersionDisplay}</span>
        <svg
          className={`h-3 w-3 transition-transform ${isOpen ? "rotate-180" : ""}`}
          fill="none"
          viewBox="0 0 24 24"
          stroke="currentColor"
        >
          <path
            strokeLinecap="round"
            strokeLinejoin="round"
            strokeWidth={2}
            d="M19 9l-7 7-7-7"
          />
        </svg>
      </button>

      {isOpen && (
        <div className="absolute left-0 mt-2 w-56 rounded-md bg-white shadow-lg outline-1 outline-black/5 z-50 max-h-80 overflow-y-auto">
          <div
            className="py-1"
            role="menu"
            aria-orientation="vertical"
            aria-labelledby="options-menu"
          >
            {isLoading ? (
              <div className="px-4 py-2 text-sm text-gray-500">
                Loading versions...
              </div>
            ) : error ? (
              <div className="px-4 py-2 text-sm text-red-600">{error}</div>
            ) : versions.length === 0 ? (
              <div className="px-4 py-2 text-sm text-gray-500">
                No versions available
              </div>
            ) : (
              versions.map((version, index) => {
                const isSelected = version.is_latest
                  ? isLatestVersion
                  : version.lock_version === currentVersion;

                // Show "latest" for the latest version, otherwise show version number
                // For the first item (which is latest), show "latest"
                // For subsequent items, show version number even if they have is_latest=true
                const displayText =
                  index === 0 && version.is_latest
                    ? "latest"
                    : `v${String(version.lock_version).substring(0, 7)}`;

                return (
                  <button
                    key={version.lock_version}
                    type="button"
                    onClick={() => handleVersionClick(version)}
                    className={`w-full text-left px-4 py-2 text-sm hover:bg-gray-100 flex items-center justify-between ${
                      isSelected
                        ? "bg-primary-50 text-primary-900"
                        : "text-gray-700"
                    }`}
                    role="menuitem"
                  >
                    <div className="flex flex-col">
                      <span className="font-medium">{displayText}</span>
                      <span className="text-xs text-gray-500">
                        {new Date(version.inserted_at).toLocaleString()}
                      </span>
                    </div>
                    {isSelected && (
                      <svg
                        className="h-4 w-4 text-primary-600"
                        fill="currentColor"
                        viewBox="0 0 20 20"
                      >
                        <path
                          fillRule="evenodd"
                          d="M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z"
                          clipRule="evenodd"
                        />
                      </svg>
                    )}
                  </button>
                );
              })
            )}
          </div>
        </div>
      )}
    </div>
  );
}
