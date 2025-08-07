import type { RelativePosition } from 'yjs';

export interface AwarenessUser {
  clientId: number;
  user: {
    id: string;
    name: string;
    color: string;
  };
  cursor?: {
    x: number;
    y: number;
  };
  selection?: {
    anchor: RelativePosition;
    head: RelativePosition;
  };
}
