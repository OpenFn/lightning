const EmptyView: React.FC = () => {
  return (
    <div className="h-16 p-4">
      <div className="text-gray-500 pb-2 justify-center flex gap-1">
        An empty JSON object will be used as the input for this run.
      </div>
    </div>
  );
};
export default EmptyView;
