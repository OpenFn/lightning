/**
 * Example component demonstrating adaptor functionality
 *
 * This shows how to use the adaptor hooks and demonstrates the
 * architecture working end-to-end.
 */

import type React from "react";
import {
  useAdaptor,
  useAdaptorCommands,
  useAdaptorManager,
  useAdaptorState,
  useAdaptors,
  useAdaptorsError,
  useAdaptorsLoading,
} from "../hooks/useAdaptors";

/**
 * Simple component showing all available adaptors
 */
export const AdaptorsList: React.FC = () => {
  const adaptors = useAdaptors();
  const isLoading = useAdaptorsLoading();
  const error = useAdaptorsError();
  const { requestAdaptors, clearError } = useAdaptorCommands();

  if (isLoading) {
    return <div className="p-4 text-gray-500">Loading adaptors...</div>;
  }

  if (error) {
    return (
      <div className="p-4 border border-red-200 bg-red-50 rounded">
        <p className="text-red-600 mb-2">Error loading adaptors: {error}</p>
        <div className="space-x-2">
          <button
            onClick={requestAdaptors}
            className="px-3 py-1 bg-blue-500 text-white rounded text-sm"
          >
            Retry
          </button>
          <button
            onClick={clearError}
            className="px-3 py-1 bg-gray-300 text-gray-700 rounded text-sm"
          >
            Clear Error
          </button>
        </div>
      </div>
    );
  }

  if (adaptors.length === 0) {
    return (
      <div className="p-4 text-gray-500">
        No adaptors available.
        <button
          onClick={requestAdaptors}
          className="ml-2 px-3 py-1 bg-blue-500 text-white rounded text-sm"
        >
          Load Adaptors
        </button>
      </div>
    );
  }

  return (
    <div className="p-4">
      <div className="flex justify-between items-center mb-4">
        <h3 className="text-lg font-medium">
          Available Adaptors ({adaptors.length})
        </h3>
        <button
          onClick={requestAdaptors}
          className="px-3 py-1 bg-blue-500 text-white rounded text-sm"
        >
          Refresh
        </button>
      </div>

      <div className="space-y-3">
        {adaptors.map((adaptor) => (
          <div
            key={adaptor.name}
            className="border border-gray-200 rounded p-3"
          >
            <div className="flex justify-between items-start mb-2">
              <h4 className="font-medium text-gray-900">{adaptor.name}</h4>
              <span className="text-xs bg-green-100 text-green-800 px-2 py-1 rounded">
                v{adaptor.latest}
              </span>
            </div>

            <p className="text-sm text-gray-600 mb-2">
              Repository: {adaptor.repo}
            </p>

            <details className="text-sm">
              <summary className="cursor-pointer text-gray-500">
                View all versions ({adaptor.versions.length})
              </summary>
              <div className="mt-2 flex flex-wrap gap-1">
                {adaptor.versions.map((version) => (
                  <span
                    key={version.version}
                    className="text-xs bg-gray-100 text-gray-700 px-2 py-1 rounded"
                  >
                    v{version.version}
                  </span>
                ))}
              </div>
            </details>
          </div>
        ))}
      </div>
    </div>
  );
};

/**
 * Component showing a specific adaptor by name
 */
export const AdaptorDetail: React.FC<{ name: string }> = ({ name }) => {
  const adaptor = useAdaptor(name);
  const isLoading = useAdaptorsLoading();

  if (isLoading) {
    return <div className="p-4 text-gray-500">Loading adaptor details...</div>;
  }

  if (!adaptor) {
    return <div className="p-4 text-gray-500">Adaptor "{name}" not found.</div>;
  }

  return (
    <div className="p-4 border border-gray-200 rounded">
      <h3 className="text-lg font-medium mb-2">{adaptor.name}</h3>
      <div className="space-y-2 text-sm">
        <p>
          <strong>Latest Version:</strong> v{adaptor.latest}
        </p>
        <p>
          <strong>Repository:</strong> {adaptor.repo}
        </p>
        <p>
          <strong>Total Versions:</strong> {adaptor.versions.length}
        </p>
        <div>
          <strong>Available Versions:</strong>
          <div className="mt-1 flex flex-wrap gap-1">
            {adaptor.versions.map((version) => (
              <span
                key={version.version}
                className={`text-xs px-2 py-1 rounded ${
                  version.version === adaptor.latest
                    ? "bg-green-100 text-green-800"
                    : "bg-gray-100 text-gray-700"
                }`}
              >
                v{version.version}
              </span>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

/**
 * Component demonstrating the comprehensive adaptor manager hook
 */
export const AdaptorManager: React.FC = () => {
  const manager = useAdaptorManager();

  return (
    <div className="p-4 border border-blue-200 bg-blue-50 rounded">
      <h3 className="text-lg font-medium mb-3">Adaptor Manager Status</h3>

      <div className="grid grid-cols-2 gap-4 text-sm">
        <div>
          <p>
            <strong>Total Adaptors:</strong> {manager.adaptors?.length || 0}
          </p>
          <p>
            <strong>Has Adaptors:</strong> {manager.hasAdaptors ? "Yes" : "No"}
          </p>
          <p>
            <strong>Is Ready:</strong> {manager.isReady ? "Yes" : "No"}
          </p>
        </div>

        <div>
          <p>
            <strong>Loading:</strong> {manager.isLoading ? "Yes" : "No"}
          </p>
          <p>
            <strong>Error:</strong> {manager.error || "None"}
          </p>
          <p>
            <strong>Last Updated:</strong>{" "}
            {manager.lastUpdated
              ? new Date(manager.lastUpdated).toLocaleTimeString()
              : "Never"}
          </p>
        </div>
      </div>

      <div className="mt-3 space-x-2">
        <button
          onClick={manager.requestAdaptors}
          className="px-3 py-1 bg-blue-500 text-white rounded text-sm"
          disabled={manager.isLoading}
        >
          {manager.isLoading ? "Loading..." : "Refresh"}
        </button>

        {manager.error && (
          <button
            onClick={manager.clearError}
            className="px-3 py-1 bg-red-500 text-white rounded text-sm"
          >
            Clear Error
          </button>
        )}
      </div>
    </div>
  );
};

/**
 * Main example component that combines everything
 */
export const AdaptorExample: React.FC = () => {
  const state = useAdaptorState();

  if (!state) {
    return (
      <div className="p-4 text-red-600">
        Adaptor functionality not available. Ensure you're within a
        SessionProvider.
      </div>
    );
  }

  return (
    <div className="space-y-6">
      <div className="border-b border-gray-200 pb-4">
        <h2 className="text-xl font-semibold">Adaptor Management Example</h2>
        <p className="text-gray-600 mt-1">
          Demonstrating the collaborative editor's adaptor functionality
        </p>
      </div>

      <AdaptorManager />

      <AdaptorsList />

      {state.adaptors.length > 0 && (
        <div>
          <h3 className="text-lg font-medium mb-3">
            Example: Specific Adaptor
          </h3>
          <AdaptorDetail name={state.adaptors[0]!.name} />
        </div>
      )}
    </div>
  );
};
