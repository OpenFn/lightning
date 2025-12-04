import {
  DocumentIcon,
  PencilSquareIcon,
  QueueListIcon,
} from '@heroicons/react/24/outline';
import { useCallback, useEffect, useMemo, useState } from 'react';

import { cn } from '#/utils/cn';
import _logger from '#/utils/logger';

import { findFirstJobFromTrigger } from '../utils/workflowGraph';

import { FilterTypes } from '../../manual-run-panel/types';
import CustomView from '../../manual-run-panel/views/CustomView';
import EmptyView from '../../manual-run-panel/views/EmptyView';
import ExistingView from '../../manual-run-panel/views/ExistingView';
import { useURLState } from '#/react/lib/use-url-state';
import type { Dataclip } from '../api/dataclips';
import * as dataclipApi from '../api/dataclips';
import { RENDER_MODES, type RenderMode } from '../constants/panel';
import { useActiveRun, useFollowRun } from '../hooks/useHistory';
import { useRunRetry } from '../hooks/useRunRetry';
import { useRunRetryShortcuts } from '../hooks/useRunRetryShortcuts';
import { useCanRun } from '../hooks/useWorkflow';
import { useKeyboardShortcut } from '../keyboard';
import type { Workflow } from '../types/workflow';

import { InspectorFooter } from './inspector/InspectorFooter';
import { InspectorLayout } from './inspector/InspectorLayout';
import { SelectedDataclipView } from './manual-run/SelectedDataclipView';
import { RunRetryButton } from './RunRetryButton';
import { Tabs } from './Tabs';

const logger = _logger.ns('ManualRunPanel').seal();

interface ManualRunPanelProps {
  workflow: Workflow;
  projectId: string;
  workflowId: string;
  jobId?: string | null;
  triggerId?: string | null;
  edgeId?: string | null;
  onClose: () => void;
  renderMode?: RenderMode;
  saveWorkflow: (options?: { silent?: boolean }) => Promise<{
    saved_at?: string;
    lock_version?: number;
  } | null>;
  onRunSubmitted?: (runId: string, dataclip?: Dataclip) => void;
  onTabChange?: (tab: TabValue) => void;
  onDataclipChange?: (dataclip: Dataclip | null) => void;
  onCustomBodyChange?: (body: string) => void;
  selectedTab?: TabValue;
  selectedDataclip?: Dataclip | null;
  customBody?: string;
}

type TabValue = 'empty' | 'custom' | 'existing';

export function ManualRunPanel({
  workflow,
  projectId,
  workflowId,
  jobId,
  triggerId,
  edgeId,
  onClose,
  renderMode = RENDER_MODES.STANDALONE,
  saveWorkflow,
  onRunSubmitted,
  onTabChange,
  onDataclipChange,
  onCustomBodyChange,
  selectedTab: selectedTabProp,
  selectedDataclip: selectedDataclipProp,
  customBody: customBodyProp,
}: ManualRunPanelProps) {
  const [selectedTabInternal, setSelectedTabInternal] =
    useState<TabValue>('empty');
  const [selectedDataclipInternal, setSelectedDataclipInternal] =
    useState<Dataclip | null>(null);
  const [customBodyInternal, setCustomBodyInternal] = useState('');

  // Use prop if provided (controlled), otherwise use internal state (uncontrolled)
  const selectedTab = selectedTabProp ?? selectedTabInternal;
  const selectedDataclip = selectedDataclipProp ?? selectedDataclipInternal;
  const customBody = customBodyProp ?? customBodyInternal;
  const [dataclips, setDataclips] = useState<Dataclip[]>([]);
  const [manuallyUnselected, setManuallyUnselected] = useState(false);

  const setSelectedTab = useCallback(
    (tab: TabValue) => {
      setSelectedTabInternal(tab);
      onTabChange?.(tab);
    },
    [onTabChange]
  );

  const setSelectedDataclip = useCallback(
    (dataclip: Dataclip | null) => {
      setSelectedDataclipInternal(dataclip);
      onDataclipChange?.(dataclip);
      setManuallyUnselected(dataclip === null);
    },
    [onDataclipChange]
  );

  const [searchQuery, setSearchQuery] = useState('');

  const setCustomBody = useCallback(
    (body: string) => {
      setCustomBodyInternal(body);
      onCustomBodyChange?.(body);
    },
    [onCustomBodyChange]
  );

  const [nextCronRunDataclipId, setNextCronRunDataclipId] = useState<
    string | null
  >(null);
  const [canEditDataclip, setCanEditDataclip] = useState(false);
  const [selectedClipType, setSelectedClipType] = useState('');
  const [selectedDates, setSelectedDates] = useState({
    before: '',
    after: '',
  });
  const [namedOnly, setNamedOnly] = useState(false);

  const { canRun: canRunWorkflow, tooltipMessage: workflowRunTooltipMessage } =
    useCanRun();

  const { params } = useURLState();
  const followedRunId = params.run ?? null;

  // Connect to run channel when following a run in standalone mode
  // In embedded mode (FullScreenIDE), parent handles the connection
  const shouldFollow =
    renderMode === RENDER_MODES.STANDALONE ? followedRunId : null;
  useFollowRun(shouldFollow);

  const currentRun = useActiveRun();

  const runContext = jobId
    ? { type: 'job' as const, id: jobId }
    : triggerId
      ? { type: 'trigger' as const, id: triggerId }
      : {
          type: 'trigger' as const,
          id: workflow.triggers[0]?.id || '',
        };

  const contextJob =
    runContext.type === 'job'
      ? workflow.jobs.find(j => j.id === runContext.id)
      : null;

  const contextTrigger =
    runContext.type === 'trigger'
      ? workflow.triggers.find(t => t.id === runContext.id)
      : null;

  const panelTitle = contextJob
    ? `Run from ${contextJob.name}`
    : contextTrigger
      ? `Run from Trigger (${contextTrigger.type})`
      : 'Run Workflow';

  // For triggers: find first connected job for dataclip fetching
  // (dataclips are associated with jobs, not triggers)
  const dataclipJobId = useMemo(() => {
    if (runContext.type === 'job') {
      return runContext.id;
    }

    const jobId = findFirstJobFromTrigger(workflow.edges, runContext.id);
    return jobId || workflow.jobs[0]?.id;
  }, [runContext, workflow.edges, workflow.jobs]);

  const {
    handleRun,
    handleRetry,
    isSubmitting,
    isRetryable,
    runIsProcessing,
    canRun,
  } = useRunRetry({
    projectId,
    workflowId,
    runContext,
    selectedTab,
    selectedDataclip,
    customBody,
    canRunWorkflow,
    workflowRunTooltipMessage,
    saveWorkflow,
    onRunSubmitted: onRunSubmitted,
    edgeId: edgeId || null,
    workflowEdges: workflow.edges,
  });

  const followedRunStep = useMemo(() => {
    if (!currentRun || !dataclipJobId) return null;
    return currentRun.steps.find(s => s.job_id === dataclipJobId) || null;
  }, [currentRun, dataclipJobId]);

  // Find the current run's input dataclip from the dataclips list
  const currentRunDataclip = useMemo(() => {
    if (!followedRunStep?.input_dataclip_id || !dataclips.length) {
      return null;
    }
    return (
      dataclips.find(dc => dc.id === followedRunStep.input_dataclip_id) || null
    );
  }, [followedRunStep, dataclips]);

  useEffect(() => {
    if (!followedRunId) {
      setSelectedDataclip(null);
      setSearchQuery('');
      setSelectedClipType('');
      setSelectedDates({ before: '', after: '' });
      setNamedOnly(false);
    }
  }, [jobId, triggerId, followedRunId, setSelectedDataclip]);

  useEffect(() => {
    setManuallyUnselected(false);
  }, [followedRunId]);

  useEffect(() => {
    if (
      !followedRunStep?.input_dataclip_id ||
      !dataclips.length ||
      manuallyUnselected
    ) {
      return;
    }

    // Only auto-select if no dataclip is currently selected
    // This allows users to manually select different dataclips
    if (selectedDataclip !== null) {
      return;
    }

    const stepDataclip = dataclips.find(
      dc => dc.id === followedRunStep.input_dataclip_id
    );

    if (stepDataclip) {
      setSelectedDataclip(stepDataclip);
      setSelectedTab('existing');
    }
  }, [
    followedRunStep,
    dataclips,
    manuallyUnselected,
    setSelectedDataclip,
    setSelectedTab,
  ]);

  useEffect(() => {
    if (!dataclipJobId) return;

    const fetchDataclips = async () => {
      try {
        const response = await dataclipApi.searchDataclips(
          projectId,
          dataclipJobId,
          '',
          {}
        );
        setDataclips(response.data);
        setNextCronRunDataclipId(response.next_cron_run_dataclip_id);
        setCanEditDataclip(response.can_edit_dataclip);

        // Auto-select next cron run dataclip (unless following a run)
        if (response.next_cron_run_dataclip_id && !followedRunId) {
          const nextCronDataclip = response.data.find(
            d => d.id === response.next_cron_run_dataclip_id
          );
          if (nextCronDataclip) {
            setSelectedDataclip(nextCronDataclip);
            setSelectedTab('existing');
          }
        }
      } catch (error) {
        logger.error('Failed to fetch dataclips:', error);
      }
    };

    void fetchDataclips();
  }, [projectId, dataclipJobId, followedRunId]);

  const buildFilters = useCallback(() => {
    const filters: Record<string, string> = {};
    if (selectedClipType) filters['type'] = selectedClipType;
    if (selectedDates.before) filters['before'] = selectedDates.before;
    if (selectedDates.after) filters['after'] = selectedDates.after;
    if (namedOnly) filters['named_only'] = 'true';
    return filters;
  }, [selectedClipType, selectedDates.before, selectedDates.after, namedOnly]);

  const getActiveFilters = useCallback(() => {
    const filters: Record<string, string | undefined> = {};
    if (selectedClipType) filters[FilterTypes.DATACLIP_TYPE] = selectedClipType;
    if (selectedDates.before)
      filters[FilterTypes.BEFORE_DATE] = selectedDates.before;
    if (selectedDates.after)
      filters[FilterTypes.AFTER_DATE] = selectedDates.after;
    if (namedOnly) filters[FilterTypes.NAMED_ONLY] = 'true';
    return filters;
  }, [selectedClipType, selectedDates.before, selectedDates.after, namedOnly]);

  const clearFilter = useCallback((filterType: FilterTypes) => {
    switch (filterType) {
      case FilterTypes.DATACLIP_TYPE:
        setSelectedClipType('');
        break;
      case FilterTypes.BEFORE_DATE:
        setSelectedDates(p => ({ ...p, before: '' }));
        break;
      case FilterTypes.AFTER_DATE:
        setSelectedDates(p => ({ ...p, after: '' }));
        break;
      case FilterTypes.NAMED_ONLY:
        setNamedOnly(false);
        break;
    }
  }, []);

  const handleSearch = useCallback(async () => {
    if (!dataclipJobId) return;

    try {
      const response = await dataclipApi.searchDataclips(
        projectId,
        dataclipJobId,
        searchQuery,
        buildFilters()
      );
      setDataclips(response.data);
    } catch (error) {
      logger.error('Failed to search dataclips:', error);
    }
  }, [projectId, dataclipJobId, searchQuery, buildFilters]);

  useEffect(() => {
    if (selectedTab !== 'existing') return;

    if (!dataclipJobId) return;

    const timeoutId = setTimeout(() => {
      const filters: Record<string, string> = {};
      if (selectedClipType) filters['type'] = selectedClipType;
      if (selectedDates.before) filters['before'] = selectedDates.before;
      if (selectedDates.after) filters['after'] = selectedDates.after;
      if (namedOnly) filters['named_only'] = 'true';

      void dataclipApi
        .searchDataclips(projectId, dataclipJobId, searchQuery, filters)
        .then(response => {
          setDataclips(response.data);
          return response;
        })
        .catch(error => {
          logger.error('Failed to search dataclips:', error);
        });
    }, 300);

    return () => clearTimeout(timeoutId);
  }, [
    selectedClipType,
    selectedDates.before,
    selectedDates.after,
    namedOnly,
    searchQuery,
    selectedTab,
    projectId,
    dataclipJobId,
  ]);

  const handleCustomBodyChange = useCallback((value: string) => {
    setCustomBody(value);
  }, []);

  const handleSelectDataclip = useCallback((dataclip: Dataclip) => {
    setSelectedDataclip(dataclip);
  }, []);

  const handleUnselectDataclip = useCallback(() => {
    setSelectedDataclip(null);
  }, []);

  const handleDataclipNameChange = useCallback(
    async (dataclipId: string, name: string | null) => {
      const response = await dataclipApi.updateDataclipName(
        projectId,
        dataclipId,
        name
      );

      // Update local state
      const updated = response.data;
      setSelectedDataclip(updated);
      setDataclips(prev => prev.map(d => (d.id === updated.id ? updated : d)));
    },
    [projectId]
  );

  useKeyboardShortcut(
    'Escape',
    () => {
      onClose();
    },
    25 // RUN_PANEL priority
  );

  // Run/retry shortcuts (standalone mode only - embedded uses IDEHeader)
  useRunRetryShortcuts({
    onRun: () => void handleRun(),
    onRetry: () => void handleRetry(),
    canRun,
    isRunning: isSubmitting || runIsProcessing,
    isRetryable,
    priority: 25, // RUN_PANEL priority
    enabled: renderMode === RENDER_MODES.STANDALONE,
  });

  const content = edgeId ? (
    <div className="flex justify-center flex-col items-center self-center h-full">
      <div className="text-gray-600">
        Select a Step or Trigger to start a Run from
      </div>
    </div>
  ) : selectedDataclip ? (
    <SelectedDataclipView
      dataclip={selectedDataclip}
      onUnselect={handleUnselectDataclip}
      onNameChange={handleDataclipNameChange}
      canEdit={canEditDataclip}
      isNextCronRun={nextCronRunDataclipId === selectedDataclip.id}
      renderMode={renderMode}
    />
  ) : (
    <div
      className={cn(
        'flex flex-col h-full min-h-0',
        renderMode === RENDER_MODES.EMBEDDED ? 'h-full mt-2' : 'flex-1 mt-4'
      )}
    >
      <Tabs
        className="mx-3"
        variant="pills"
        value={selectedTab}
        onChange={value => setSelectedTab(value)}
        options={[
          { value: 'empty', label: 'Empty', icon: DocumentIcon },
          {
            value: 'custom',
            label: 'Custom',
            icon: PencilSquareIcon,
          },
          {
            value: 'existing',
            label: 'Existing',
            icon: QueueListIcon,
          },
        ]}
      />

      {selectedTab === 'empty' && <EmptyView />}
      {selectedTab === 'custom' && (
        <CustomView
          pushEvent={(_event, data: unknown) => {
            // Type guard for data shape
            if (
              data &&
              typeof data === 'object' &&
              'manual' in data &&
              data.manual &&
              typeof data.manual === 'object' &&
              'body' in data.manual &&
              typeof data.manual.body === 'string'
            ) {
              handleCustomBodyChange(data.manual.body);
            }
          }}
          renderMode={renderMode}
        />
      )}
      {selectedTab === 'existing' && (
        <ExistingView
          dataclips={dataclips}
          query={searchQuery}
          setQuery={setSearchQuery}
          setSelected={handleSelectDataclip}
          filters={getActiveFilters()}
          selectedClipType={selectedClipType}
          setSelectedClipType={setSelectedClipType}
          clearFilter={clearFilter}
          selectedDates={selectedDates}
          setSelectedDates={setSelectedDates}
          namedOnly={namedOnly}
          setNamedOnly={setNamedOnly}
          onSubmit={() => {
            void handleSearch();
          }}
          fixedHeight={false}
          currentRunDataclip={currentRunDataclip}
          nextCronRunDataclipId={nextCronRunDataclipId}
          renderMode={renderMode}
        />
      )}
    </div>
  );

  if (renderMode === RENDER_MODES.EMBEDDED) {
    return content;
  }

  return (
    <InspectorLayout
      title={panelTitle}
      onClose={onClose}
      fixedHeight={true}
      showBackButton={true}
      footer={
        <InspectorFooter
          rightButtons={
            <RunRetryButton
              isRetryable={isRetryable}
              isDisabled={!canRun}
              isSubmitting={isSubmitting || runIsProcessing}
              onRun={() => {
                void handleRun();
              }}
              onRetry={() => {
                void handleRetry();
              }}
              buttonText={{
                run: 'Run Workflow Now',
                retry: 'Run (retry)',
                processing: 'Processing',
              }}
              showKeyboardShortcuts={true}
              disabledTooltip={workflowRunTooltipMessage}
            />
          }
        />
      }
    >
      {content}
    </InspectorLayout>
  );
}
