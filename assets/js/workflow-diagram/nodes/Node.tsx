import React, { memo, type MouseEvent } from 'react';
import { Handle, type NodeProps } from '@xyflow/react';

import Shape from '../components/Shape';
import ErrorMessage from '../components/ErrorMessage';
import { nodeIconStyles, nodeLabelStyles } from '../styles';
import type { RunStep } from '#/workflow-store/store';
import formatDate from '../../utils/formatDate';

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
  const textColorClass = hasErrors ? 'text-red-500' : '';

  if (children && (children as any).length) {
    return (
      <p
        className={`line-clamp-2 align-left text-m max-w-[120px] text-ellipsis overflow-hidden ${textColorClass}`}
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
  type
}: BaseNodeProps) => {
  const isTriggerNode = type === "trigger";
  const runData = data?.runData as RunStep | undefined;
  const isErrorRun = runData?.exit_reason !== "success";
  // TODO: remember triggers
  const didRun = data.isRun ? !!runData : true

  const { width, height, anchorx, strokeWidth, style } = nodeIconStyles(
    selected,
    hasErrors(errors),
    runData?.exit_reason
  );

  const nodeOpacity = data.dropTargetError ? 0.4 : 1;

  return (
    <div className={`group ${didRun ? "opacity-100" : "opacity-30"}`} data-a-node>
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
          <svg
            style={{
              maxWidth: '110px',
              maxHeight: '110px',
              opacity: nodeOpacity,
              overflow: "visible"
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
          {runData && !isTriggerNode ? <div
            className={`flex justify-center items-center absolute -left-2 -top-2 border-2 w-6 h-6 rounded-full ${isErrorRun ? "border-red-600 bg-red-100" : "border-green-600 bg-green-100"}`}
            data-tooltip={isErrorRun ? runData?.error_type : "Successful run"}
            data-tooltip-placement="top"
          >
            {isErrorRun ?
              <span className='hero-exclamation-circle w-3 h-3'></span> :
              <span className='hero-check w-3 h-3'></span>
            }
          </div> : null}
          {runData?.startNode ? <div
            className={`absolute -top-2 flex gap-2 items-center z-30`}
            style={{
              left: "calc(100% - 24px)"
            }}
            data-tooltip={`Run by ${runData.startBy || "unknown"}`}
            data-tooltip-placement="top"
          >
            <div className='flex justify-center items-center border-2 w-6 h-6 rounded-full text-slate-50 border-slate-700 bg-slate-600'>
              <span className='hero-play-solid w-3 h-3'></span>
            </div>
          </div> : null}
          {runData?.started_at ? <div
            className={`absolute top-2 ml-2 flex gap-2 items-center text-nowrap`}
            style={{
              left: "calc(100% + 6px)"
            }}
          >
            {formatDate(new Date(runData.started_at))}
          </div> : null}
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
        <div className="flex flex-col mt-8 ml-2 absolute left-[116px] top-0 pointer-events-none min-w-[275px]">
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
          className={`flex flex-row items-center
                    opacity-0  ${(!data.isActiveDropTarget && 'group-hover:opacity-100') ??
            ''
            }
                    transition duration-150 ease-in-out`}
        >
          {toolbar()}
        </div>
      )}
    </div>
  );
};

Node.displayName = 'Node';

export default memo(Node);
