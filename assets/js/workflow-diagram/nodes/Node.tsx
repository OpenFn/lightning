import { Handle, type NodeProps } from '@xyflow/react';
import React, { memo } from 'react';

import { Tooltip } from '../../collaborative-editor/components/Tooltip';
import { cn } from '../../utils/cn';
import { duration } from '../../utils/duration';
import formatDate from '../../utils/formatDate';
import type { RunStep } from '../../workflow-store/store';
import ErrorMessage from '../components/ErrorMessage';
import { renderIcon } from '../components/RunIcons';
import Shape from '../components/Shape';
import { nodeIconStyles, nodeLabelStyles } from '../styles';

type NodeData = any;

type BaseNodeProps = NodeProps<NodeData> & {
  shape?: 'circle' | 'rect';
  primaryIcon?: any;
  secondaryIcon?: any;
  label?: string;
  sublabel?: string;
  toolbar?: any;
  errors?: any;
};

type ErrorObject = {
  [key: string]: string[];
};

type LabelProps = React.PropsWithChildren<{
  hasErrors?: boolean;
}>;

function errorsMessage(errors: ErrorObject): string {
  const messages = Object.entries(errors).map(([key, errorArray]) => {
    return `${errorArray.join(', ')}`;
  });

  return messages.join(', ');
}

const hasErrors = (errors: ErrorObject | null | undefined): boolean => {
  if (!errors) return false;

  return Object.values(errors).some(errorArray => errorArray.length > 0);
};

const Label: React.FC<LabelProps> = ({ children, hasErrors = false }) => {
  if (children && (children as any).length) {
    return (
      <p
        className={cn(
          'line-clamp-2 align-left text-m max-w-[220px] text-ellipsis overflow-hidden',
          hasErrors && 'text-red-500'
        )}
      >
        {children}
      </p>
    );
  }
  return null;
};

const SubLabel = ({ children }: React.PropsWithChildren) => {
  if (children && (children as any).length) {
    return (
      <p className="line-clamp-2 align-left text-sm text-slate-500">
        {children}
      </p>
    );
  }
  return null;
};

const Node = ({
  id,
  // standard  react flow stuff
  isConnectable,
  selected,
  targetPosition,
  sourcePosition,
  data,

  // custom stuff
  toolbar,
  shape,
  label, // main label which appears to the right
  sublabel, // A smaller label to the right
  primaryIcon, // displayed inside the SVG shape
  secondaryIcon,

  errors,
  type,
}: BaseNodeProps) => {
  const isTriggerNode = type === 'trigger';
  const runData = data?.runData as RunStep | undefined;
  const startInfo = data?.startInfo as
    | { started_at: string; startBy: string }
    | undefined;
  // TODO: remember triggers
  const didRun = data.isRun
    ? !!runData || (!!data?.startInfo && isTriggerNode)
    : true;

  const { width, height, anchorx, strokeWidth, style } = nodeIconStyles(
    selected,
    hasErrors(errors),
    runData?.exit_reason
  );

  const nodeOpacity = data.dropTargetError ? 0.4 : 1;

  return (
    <div
      className={cn('group', didRun ? 'opacity-100' : 'opacity-30')}
      data-a-node
      data-id={id}
      data-testid={type === 'trigger' ? `trigger-node-${id}` : `job-node-${id}`}
      data-valid-drop-target={
        data.isValidDropTarget !== undefined
          ? String(data.isValidDropTarget)
          : undefined
      }
      data-active-drop-target={data.isActiveDropTarget ? 'true' : undefined}
      data-drop-target-error={data.dropTargetError || undefined}
    >
      <div className="flex flex-row cursor-pointer">
        <div className="relative">
          {targetPosition && (
            <>
              {/*
                This is the standard handle for existing connections
                Setting the id ensures that edges will connect here
              */}
              <Handle
                id={id}
                type="target"
                isConnectable={false}
                position={targetPosition}
                style={{
                  visibility: 'hidden',
                  height: 0,
                  top: 0,
                  left: strokeWidth + anchorx,
                }}
              />

              {/* This is the fancy, oversized drop handle */}
              <Handle
                type="target"
                isConnectable={isConnectable}
                // handles have a built-in way of updating styles when connecting - is this better?
                // See https://reactflow.dev/examples/interaction/validation
                style={{
                  visibility: data.isValidDropTarget ? 'visible' : 'hidden',

                  // abuse the handle style to make the whole node the drop target
                  left: '52px',
                  top: '52px',
                  width: '128px',
                  height: '128px',
                  zIndex: 1000,
                  backgroundColor: data.isActiveDropTarget
                    ? 'rgba(79, 70, 229, 0.2)'
                    : 'transparent',
                  borderColor: 'rgb(79, 70, 229)',
                  borderWidth: '4px',
                  borderStyle: data.isActiveDropTarget ? 'solid' : 'dashed',
                  borderRadius: '20%',
                }}
              />
            </>
          )}
          {runData && !isTriggerNode ? (
            <div className="absolute -left-2 -top-2 pointer-events-auto z-10">
              {renderIcon(runData.exit_reason ?? 'pending', {
                tooltip: runData?.error_type ?? 'Step completed successfully',
              })}
            </div>
          ) : null}
          {data.duplicateRunCount > 1 && !isTriggerNode ? (
            <div
              className="absolute -right-1 -top-2"
              data-tooltip={`This step ran ${data.duplicateRunCount} times; view other executions via the Inspector or History page.`}
              data-tooltip-placement="top"
            >
              <div className="flex justify-center items-center w-7 h-7 rounded-full text-white bg-primary-600 shadow-sm">
                <span className="text-xs font-bold">
                  {data.duplicateRunCount}
                </span>
              </div>
            </div>
          ) : null}
          {startInfo ? (
            <div
              className="absolute -top-2 flex gap-2 items-center pointer-events-auto z-10"
              style={{
                left: 'calc(100% - 24px)',
              }}
            >
              <Tooltip content={`Started by ${startInfo.startBy}`} side="top">
                <div className="flex justify-center items-center w-7 h-7 rounded-full text-slate-50 border-slate-700 bg-slate-600">
                  <span className="hero-play-solid w-3 h-3"></span>
                </div>
              </Tooltip>
            </div>
          ) : null}
          {runData?.started_at && runData.finished_at ? (
            <div
              className={`absolute top-2 ml-2 flex gap-2 items-center text-nowrap font-mono`}
              style={{
                left: 'calc(100% + 6px)',
              }}
            >
              {isTriggerNode
                ? formatDate(new Date(runData.started_at))
                : duration(runData.started_at, runData.finished_at)}
            </div>
          ) : null}
          {isTriggerNode && startInfo?.started_at ? (
            <div
              className={`absolute top-2 ml-2 flex gap-2 items-center text-nowrap font-mono`}
              style={{
                left: 'calc(100% + 6px)',
              }}
            >
              {formatDate(new Date(startInfo.started_at))}
            </div>
          ) : null}
          <svg
            style={{
              maxWidth: '110px',
              maxHeight: '110px',
              opacity: nodeOpacity,
              overflow: 'visible',
            }}
          >
            <Shape
              shape={shape}
              width={width}
              height={height}
              strokeWidth={strokeWidth}
              styles={style}
            />
          </svg>
          {primaryIcon && (
            <div
              style={{
                position: 'absolute',
                // Position is half of the difference of the actual width, offset for stroke
                left: 0.175 * width + strokeWidth,
                top: 0.175 * height + strokeWidth,
                height: `${0.65 * height}px`,
                width: `${0.65 * width}px`,
                ...nodeLabelStyles(selected),
                opacity: nodeOpacity,
              }}
            >
              {typeof primaryIcon === 'string' ? (
                <div
                  className="font-bold"
                  style={{
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {primaryIcon}
                </div>
              ) : (
                primaryIcon
              )}
            </div>
          )}
          {secondaryIcon && (
            <div
              style={{
                position: 'absolute',
                left: '2%', // You can adjust these values for precise positioning
                top: '2%',
                height: `${0.3 * height}px`, // Adjusting size for secondary icon
                width: `${0.3 * width}px`,
                ...nodeLabelStyles(selected),
              }}
            >
              {typeof secondaryIcon === 'string' ? (
                <div
                  className="font-bold"
                  style={{
                    overflow: 'hidden',
                    textOverflow: 'ellipsis',
                    whiteSpace: 'nowrap',
                  }}
                >
                  {secondaryIcon}
                </div>
              ) : (
                secondaryIcon
              )}
            </div>
          )}
        </div>
        {/* TODO the drag source should ideally be in the centre and behind the node */}
        {sourcePosition && (
          <Handle
            type="source"
            isConnectable={isConnectable}
            position={sourcePosition}
            style={{
              visibility: 'hidden',
              height: 0,
              top: height,
              left: strokeWidth + anchorx,
            }}
          />
        )}
        <div className="flex flex-col mt-8 absolute left-[116px] top-0 pointer-events-none min-w-[275px]">
          <Label hasErrors={hasErrors(errors)}>{label}</Label>
          <SubLabel>{sublabel}</SubLabel>
          {data.isActiveDropTarget &&
            typeof data.dropTargetError === 'string' && (
              <ErrorMessage>{data.dropTargetError}</ErrorMessage>
            )}
          {hasErrors(errors) && (
            <ErrorMessage>{errorsMessage(errors)}</ErrorMessage>
          )}
        </div>
      </div>
      {toolbar && (
        <div
          style={{
            width: `${width}px`,
            marginLeft: '2px',
            marginTop: '-18px',
            justifyContent: 'center',
          }}
          className={cn(
            'flex flex-row items-center opacity-0 transition duration-150 ease-in-out',
            !data.isActiveDropTarget && 'group-hover:opacity-100'
          )}
        >
          {toolbar()}
        </div>
      )}
    </div>
  );
};

Node.displayName = 'Node';

export default memo(Node);
