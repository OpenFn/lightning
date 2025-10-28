import { CheckIcon, PencilIcon, XMarkIcon } from "@heroicons/react/24/outline";
import { useCallback, useState } from "react";

import { DataclipViewer } from "../../../react/components/DataclipViewer";
import type { Dataclip } from "../../api/dataclips";
import { Button } from "../Button";

interface SelectedDataclipViewProps {
  dataclip: Dataclip;
  onUnselect: () => void;
  onNameChange: (dataclipId: string, name: string | null) => Promise<void>;
  canEdit: boolean;
  isNextCronRun: boolean;
}

export function SelectedDataclipView({
  dataclip,
  onUnselect,
  onNameChange,
  canEdit,
  isNextCronRun,
}: SelectedDataclipViewProps) {
  const [isEditingName, setIsEditingName] = useState(false);
  const [editedName, setEditedName] = useState(dataclip.name || "");
  const [isSaving, setIsSaving] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const handleSaveName = useCallback(async () => {
    setIsSaving(true);
    setError(null);
    try {
      await onNameChange(dataclip.id, editedName || null);
      setIsEditingName(false);
    } catch (err) {
      setError(err instanceof Error ? err.message : "Failed to save name");
    } finally {
      setIsSaving(false);
    }
  }, [dataclip.id, editedName, onNameChange]);

  return (
    <div className="flex flex-col h-full px-6 pt-4 pb-6">
      {/* Header */}
      <div className="flex items-center justify-between pb-4">
        <div className="flex-1">
          {isEditingName ? (
            <div className="flex gap-2">
              <input
                type="text"
                value={editedName}
                onChange={e => setEditedName(e.target.value)}
                className="flex-1 rounded-md border-gray-300
                  shadow-sm focus:border-indigo-500
                  focus:ring-indigo-500 sm:text-sm"
                placeholder="Dataclip name"
                autoFocus
              />
              <Button
                variant="primary"
                onClick={handleSaveName}
                disabled={isSaving}
                className="!p-2"
              >
                <CheckIcon className="h-4 w-4" />
              </Button>
              <Button
                variant="secondary"
                onClick={() => {
                  setIsEditingName(false);
                  setEditedName(dataclip.name || "");
                  setError(null);
                }}
                disabled={isSaving}
                className="!p-2"
              >
                <XMarkIcon className="h-4 w-4" />
              </Button>
            </div>
          ) : (
            <>
              <div className="flex items-center gap-2">
                <h3 className="font-medium text-gray-900">
                  {dataclip.name || "Unnamed"}
                </h3>
                {canEdit && (
                  <button
                    onClick={() => setIsEditingName(true)}
                    className="text-gray-400 hover:text-gray-600"
                  >
                    <PencilIcon className="h-4 w-4" />
                  </button>
                )}
              </div>
              <div
                className="flex items-center gap-2 text-xs
                  text-gray-500 mt-1"
              >
                <span className="capitalize">
                  {dataclip.type.replace("_", " ")}
                </span>
                <span>•</span>
                <span>
                  {new Date(dataclip.inserted_at).toLocaleDateString()}
                </span>
              </div>
            </>
          )}
          {error && <div className="mt-2 text-sm text-red-600">{error}</div>}
        </div>
        <button
          onClick={onUnselect}
          className="ml-4 text-gray-400 hover:text-gray-600"
        >
          <XMarkIcon className="h-5 w-5" />
        </button>
      </div>

      {/* Next Cron Run Warning */}
      {isNextCronRun && (
        <div className="alert-warning flex flex-col gap-1 px-3 py-2 rounded-md border mb-4">
          <span className="text-sm font-medium">
            Default Next Input for Cron
          </span>
          <span className="text-xs">
            This workflow has a "cron" trigger, and by default it will use the
            input below for its next run. You can override that by starting a
            manual run with an empty input or a custom input at any time.
          </span>
        </div>
      )}

      {/* Body Preview */}
      <div className="flex-1 overflow-hidden">
        <DataclipViewer dataclipId={dataclip.id} />
      </div>
    </div>
  );
}
