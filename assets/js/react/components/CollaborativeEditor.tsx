export type CollaborativeEditorProps = {
  workflow_id: string;
  workflow_name: string;
};

export const CollaborativeEditor = ({
  workflow_id,
  workflow_name,
}: CollaborativeEditorProps) => {
  return (
    <div className="collaborative-editor">
      <div className="bg-blue-50 border border-blue-200 rounded-lg p-6 text-center">
        <h2 className="text-2xl font-bold text-blue-900 mb-4">
          🚀 Hello from React!
        </h2>
        <p className="text-blue-700 mb-2">
          Collaborative Editor for: <strong>{workflow_name}</strong>
        </p>
        <p className="text-blue-600 text-sm">Workflow ID: {workflow_id}</p>
        <div className="mt-4 p-4 bg-white rounded border">
          <p className="text-gray-600 text-sm">
            This is a React component rendered inside Phoenix LiveView!
            <br />
            Ready for Yjs collaborative editing implementation.
          </p>
        </div>
      </div>
    </div>
  );
};
