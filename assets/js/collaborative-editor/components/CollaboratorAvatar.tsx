import { Tooltip } from "./Tooltip";

interface CollaboratorAvatarProps {
  initials: string;
  color: string;
  isActive: boolean;
  tooltip: string;
}

const CollaboratorAvatar: React.FC<CollaboratorAvatarProps> = ({
  color,
  initials,
  isActive,
  tooltip,
}) => {
  return (
    <Tooltip content={tooltip} side="right">
      <div
        className={`relative inline-flex items-center justify-center rounded-full border-2 ${isActive ? "border-green-500" : "border-gray-500 "}`}
      >
        <div
          className="w-5 h-5 rounded-full flex items-center justify-center font-normal text-[9px] font-semibold text-white cursor-default"
          style={{
            backgroundColor: color,
            textShadow:
              "1px 0 0 rgba(0, 0, 0, 0.5), 0 -1px 0 rgba(0, 0, 0, 0.5), 0 1px 0 rgba(0, 0, 0, 0.5), -1px 0 0 rgba(0, 0, 0, 0.5)",
          }}
        >
          {initials}
        </div>
      </div>
    </Tooltip>
  );
};

export default CollaboratorAvatar;
