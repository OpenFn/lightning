const EmptyView: React.FC = () => {
  return (
    <div className="px-6 pt-4 pb-6">
      <div className="text-gray-500 pb-2 justify-center flex gap-1">
        An empty JSON object will be used as the input for this run.
      </div>
    </div>
  );
};
export default EmptyView;
