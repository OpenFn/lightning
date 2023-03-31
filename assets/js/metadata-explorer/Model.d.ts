export type ModelNode = {
  label: string;
  name: string;
  type: string;
  datatype: string;
  children: Record<string, ModelNode[]> | ModelNode[];
};
