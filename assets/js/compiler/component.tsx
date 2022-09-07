import React, { ChangeEvent } from 'react';
import { createRoot } from 'react-dom/client';
import create from 'zustand';
import LoadingIcon from './LoadingIcon';
import ReactMarkdown from 'react-markdown';
import InfoCircle from './InfoIcon';
import ErrorIcon from './ErrorIcon';

interface CompilerComponentState {
  specifier: string | null;
  loading: boolean;
  error: string | null;
  statusMessage: string | null;
  operations: {}[];
  selectedOperation: string | undefined;
  setOperation: (e: ChangeEvent<HTMLSelectElement>) => void;
  loadModule: () => void;
}

const useStore = create<CompilerComponentState>((set, get) => ({
  specifier: null,
  error: null,
  loading: false,
  statusMessage: null,
  operations: [],
  selectedOperation: undefined,
  setOperation(e) {
    set({ selectedOperation: e.target.value });
  },
  async loadModule() {
    const specifier = get().specifier;

    if (specifier) {
      set({ loading: true, statusMessage: 'Loading compiler...', error: null });

      const { Pack, Project, describeDts } = await import('@openfn/compiler');
      const project = new Project();

      set({ statusMessage: 'Loading package...' });
      const pack = await Pack.fromUnpkg(specifier);

      const packageOrDts = /(?:package.json)|(?:\.d\.ts$)/i;

      if (!pack.types) {
        set({ error: 'no-types', loading: false });
        // throw new Error(
        //   `No 'types' field found for ${pack.specifier}`
        // );
        return;
      }

      const files = await pack.getFiles(
        pack.fileListing.filter(path => packageOrDts.test(path))
      );

      project.addToFS(files);
      project.createFile(files.get(pack.types)!, pack.types);

      const operations = describeDts(project, pack.types);

      set({
        operations,
        loading: false,
        statusMessage: null,
        error: null,
      });
    }
  },
}));

function ModuleSelector() {
  const operations = useStore(state => state.operations);
  const selectedOperation = useStore(state => state.selectedOperation);
  const setOperation = useStore(state => state.setOperation);
  const operationComment = useStore(
    state =>
      state.operations.find(op => op.name == state.selectedOperation)?.comment
  );

  return (
    <>
      <select
        name="operation-selector"
        id="operation-selector"
        value={selectedOperation}
        onChange={setOperation}
        className="block w-full rounded-md border-gray-300 shadow-sm focus:border-indigo-300 focus:ring focus:ring-indigo-200 focus:ring-opacity-50"
      >
        <option></option>
        {operations.map(op => (
          <option key={op.name} value={op.name}>
            {op.name}
          </option>
        ))}
      </select>
      {selectedOperation ? (
        <div className="rounded-md p-2 border-2 border-indigo-100 bg-indigo-100 mt-2 text-sm transition-all">
          <ReactMarkdown>{operationComment}</ReactMarkdown>
        </div>
      ) : (
        <div className="rounded-md p-2 border-dashed border-2 border-indigo-100 mt-2 text-sm transition-all">
          Select an operation.
        </div>
      )}
    </>
  );
}

function NoSpecifier() {
  return (
    <div className="rounded-md p-2 border-dashed border-2 border-indigo-100 text-sm transition-all">
      <div className="inline-block align-middle text-indigo-500 mr-2">
        <InfoCircle />
      </div>
      <span className="inline-block align-middle">No module specified.</span>
    </div>
  );
}

const errorStrings = {
  'no-types': function NoTypes() {
    return (
      <div className="rounded-md p-2 border-dashed border-2 border-indigo-100 text-sm transition-all">
        <div className="inline-block align-middle text-indigo-500 mr-2">
          <InfoCircle />
        </div>
        <span className="inline-block align-middle">
          No type information found.
        </span>
      </div>
    );
  },
  unknown: function UnknownError() {
    return (
      <div>
        <div className="inline-block align-middle mr-">
          <ErrorIcon />
        </div>
        <span className="inline-block align-middle">Something went wrong.</span>
      </div>
    );
  },
};

function Outer() {
  const specifier = useStore(state => state.specifier);
  const isLoading = useStore(state => state.loading);
  const statusMessage = useStore(state => state.statusMessage);
  const error = useStore(state => state.error);

  if (!specifier) {
    return <NoSpecifier />;
  }

  if (isLoading) {
    return (
      <div>
        <div className="inline-block align-middle ml-2 mr-3 text-indigo-500">
          <LoadingIcon />
        </div>
        <span className="inline-block align-middle">{statusMessage}</span>
      </div>
    );
  }

  if (error) {
    const ErrorComponent = errorStrings[error] || errorStrings['unknown'];

    return <ErrorComponent />;
  }

  return <ModuleSelector />;
}

export function mount(el: Element, { specifier }) {
  const componentRoot = createRoot(el);
  const unsubscribeFromStore = useStore.subscribe((state, prevState) => {
    if (state.specifier !== prevState.specifier) {
      state.loadModule();
    }
  });

  useStore.setState({ specifier });

  function update(state: Partial<CompilerComponentState>) {
    useStore.setState(state);
  }

  function unmount() {
    unsubscribeFromStore();
    componentRoot.unmount();
    useStore.setState({});
  }

  // Default state
  componentRoot.render(<Outer />);

  return {
    update,
    unmount,
  };
}
