export type ModelNode = {
  label: string;
  name: string;
  type: string;
  children: Record<string, ModelNode[]> | ModelNode[];
};
