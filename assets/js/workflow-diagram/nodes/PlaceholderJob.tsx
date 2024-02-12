import React, {
  SyntheticEvent,
  memo,
  useCallback,
  useRef,
  useState,
} from 'react';
import { Handle, NodeProps, Position } from 'reactflow';
import {
  CheckCircleIcon,
  InformationCircleIcon,
  XMarkIcon,
} from '@heroicons/react/24/outline';
import { NODE_HEIGHT, NODE_WIDTH } from '../constants';

type NodeData = any;

type ValidationResult = {
  isValid: boolean;
  message: string;
};

const iconBaseStyle = 'mx-1';
const iconNormalStyle =
  iconBaseStyle + ' text-primary-500 hover:text-primary-900';
const iconErrorStyle = iconBaseStyle + ' text-red-500 hover:text-red-600';

// Dispatch an event up to the WorkflowDiagram
// This works better than interfacing to the store correctly
// because the Workflow Diagram can control selection
const dispatch = (
  el: HTMLElement,
  eventName: 'commit-placeholder' | 'cancel-placeholder',
  data: Record<string, unknown>
) => {
  const e = new CustomEvent(eventName, {
    bubbles: true,
    detail: data,
  });
  el.dispatchEvent(e);
};

const PlaceholderJobNode = ({ id, selected }: NodeProps<NodeData>) => {
  const textRef = useRef<HTMLInputElement>();

  const [validationResult, setValidationResult] = useState<ValidationResult>({
    isValid: true,
    message: '',
  });

  const handleKeyDown = (evt: React.KeyboardEvent<HTMLInputElement>) => {
    if (evt.code === 'Escape') {
      handleCancel();
      return;
    }
    if (evt.target.value.trim() === '') {
      setValidationResult({
        isValid: false,
        message: 'Name cannot be empty.',
      });
      return;
    }
    if (evt.code === 'Enter') {
      validationResult.isValid && handleCommit();
    }
  };

  const handleChange = (evt: React.ChangeEvent<HTMLInputElement>) => {
    setValidationResult(validateName(evt.target.value));
  };

  const validateName = (name: string): ValidationResult => {
    if (name.length > 100) {
      return {
        isValid: false,
        message: 'Name should not exceed 100 characters.',
      };
    }

    const regex = /^[a-zA-Z0-9_\- ]*$/;
    if (!regex.test(name)) {
      return {
        isValid: false,
        message:
          'Name can only contain alphanumeric characters, underscores, dashes, and spaces.',
      };
    }

    return {
      isValid: true,
      message: 'Valid name.',
    };
  };

  // TODO what if a name hasn't been entered?
  const handleCommit = useCallback(
    (evt?: SyntheticEvent) => {
      if (textRef.current) {
        dispatch(textRef.current, 'commit-placeholder', {
          id,
          name: textRef.current.value,
        });
      }
      evt?.stopPropagation();
    },
    [textRef]
  );

  const handleCancel = useCallback(
    (evt?: SyntheticEvent) => {
      if (textRef.current) {
        dispatch(textRef.current, 'cancel-placeholder', { id });
      }
      evt?.stopPropagation();
    },
    [textRef]
  );

  return (
    <div
      className={[
        'bg-transparent',
        'cursor-pointer',
        'h-full',
        'p-1',
        'rounded-md',
        'shadow-sm',
        'text-center',
        'text-xs',
        'border-dashed',
        'border-2',
        validationResult.isValid
          ? 'border-indigo-500'
          : 'border-red-500 text-red-500',
        selected ? 'border-opacity-70' : 'border-opacity-30',
      ].join(' ')}
      style={{
        width: `${NODE_WIDTH}px`,
        height: `${NODE_HEIGHT}px`,

        // TODO for now, just curdely align this placeholder so that it sits in the right position
        // We'll later change the placeholder to look more consistent
        // (or otherwise come back and do this nicely)
        marginLeft: '-35px', // magic number
      }}
    >
      <Handle
        type="target"
        position={Position.Top}
        isConnectable
        style={{
          visibility: 'hidden',
          border: 'none',
          height: 0,
          left: '52px', // half node width + stroke
        }}
      />
      <div
        className={['h-full', 'text-center', 'items-center']
          .filter(Boolean)
          .join(' ')}
      >
        <div
          className={[
            'flex',
            'flex-row',
            'justify-center',
            'h-full',
            'text-center',
          ]
            .filter(Boolean)
            .join(' ')}
        >
          <XMarkIcon
            className={
              validationResult.isValid
                ? `${iconNormalStyle}`
                : `${iconErrorStyle}`
            }
            title="Cancel creation of this job"
            onClick={handleCancel}
          />
          <input
            type="text"
            ref={textRef}
            autoFocus
            data-placeholder={id}
            className={[
              'line-clamp-2',
              'align-middle',
              'focus:outline-none',
              'focus:ring-0',
              'border-none',
              'bg-transparent',
              'text-center',
              'text-xs',
            ].join(' ')}
            onKeyDown={handleKeyDown}
            onChange={handleChange}
          />
          {validationResult.isValid ? (
            <CheckCircleIcon
              className={iconNormalStyle}
              title="Create this job"
              onClick={handleCommit}
            />
          ) : (
            <InformationCircleIcon
              className={iconErrorStyle}
              title={validationResult.message}
            />
          )}
        </div>
      </div>
    </div>
  );
};

PlaceholderJobNode.displayName = 'PlaceholderJobNode';

export default memo(PlaceholderJobNode);
