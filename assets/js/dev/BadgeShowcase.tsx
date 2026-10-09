import { Badge, type BadgeColor } from '#/ui/Badge';

const colors: BadgeColor[] = [
  'neutral',
  'success',
  'warning',
  'danger',
  'info',
  'brand',
  'orange',
  'dark',
];

// Mounted on /dev/components next to the HEEx version, row for row.
export const BadgeShowcase = () => (
  <div className="flex flex-col gap-y-3">
    <div className="flex flex-wrap items-center gap-2">
      {colors.map(color => (
        <Badge key={color} color={color}>
          {color}
        </Badge>
      ))}
    </div>
    <div className="flex flex-wrap items-center gap-2">
      {colors.map(color => (
        <Badge key={color} color={color} size="small">
          {color}
        </Badge>
      ))}
    </div>
    <div className="flex flex-wrap items-center gap-2">
      <Badge mono>a1b2c3d</Badge>
      <Badge color="success" icon="hero-bolt">
        Webhook
      </Badge>
      <Badge className="max-w-32">
        <span className="truncate">a-very-long-sandbox-name</span>
      </Badge>
      <Badge color="brand" onRemove={() => {}} removeLabel="Remove Project A">
        Project A
      </Badge>
    </div>
    <div className="flex flex-wrap items-center gap-4">
      {colors.map(color => (
        <Badge key={color} color={color} dot>
          {color}
        </Badge>
      ))}
      <Badge color="info" dot pulse>
        Running
      </Badge>
    </div>
  </div>
);
