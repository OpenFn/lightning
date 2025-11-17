import {
  CheckCircleIcon,
  InformationCircleIcon,
} from '@heroicons/react/24/outline';
import { Handle, type NodeProps, Position } from '@xyflow/react';
import React, {
  type SyntheticEvent,
  memo,
  useCallback,
  useRef,
  useState,
} from 'react';

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

const PlaceholderJobNode = ({ id, data, selected }: NodeProps<NodeData>) => {
  const textRef = useRef<HTMLInputElement | null>(null);

  const [jobName, setJobName] = useState('');

  const [validationResult, setValidationResult] = useState<ValidationResult>({
    isValid: true,
    message: '',
  });

  const handleKeyDown = (evt: React.KeyboardEvent<HTMLInputElement>) => {
    if (evt.code === 'Escape') {
      handleCancel();
      return;
    }
    if (evt.currentTarget.value.trim() === '') {
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
    [id]
  );

  const handleCancel = useCallback(
    (evt?: SyntheticEvent) => {
      if (textRef.current) {
        dispatch(textRef.current, 'cancel-placeholder', { id });
      }
      evt?.stopPropagation();
    },
    [id]
  );

  return (
    <div
      className={[
        'bg-transparent',
        'cursor-pointer',
        'h-full',
        'p-1',
        'rounded-md',
        'shadow-xs',
        'text-center',
        'text-xs',
        'border-2',
        validationResult.isValid
          ? 'border-indigo-500'
          : 'border-red-500 text-red-500',
        selected ? 'border-indigo-500/70' : 'border-indigo-500/30',
      ].join(' ')}
      style={{
        width: '180px',
        height: '40px',

        // TODO for now, just crudely align this placeholder so that it sits in the right position
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
          <input
            type="text"
            ref={inputRef => {
              // assign ref and force focus
              textRef.current = inputRef;
              inputRef?.focus();
            }}
            autoFocus
            value={jobName}
            onChange={e => {
              setJobName(e.target.value);
              handleChange(e);
            }}
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
