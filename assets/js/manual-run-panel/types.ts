export enum SeletableOptions {
  EXISTING,
  EMPTY,
  CUSTOM,
  IMPORT,
}

export interface Dataclip {
  id: string;
  body: {
    data: Record<string, unknown>;
    request: {
      headers: {
        accept: string;
        host: string;
        'user-agent': string;
      };
      method: string;
      path: string[];
      query_params: Record<string, unknown>;
    };
  };
  request: null;
  type: 'http_request';
  wiped_at: string | null;
  project_id: string;
  inserted_at: string;
  updated_at: string;
}

export const DataclipTypes = [
  'http_request',
  'global',
  'step_result',
  'saved_input',
  'kafka',
];

export enum FilterTypes {
  DATACLIP_TYPE = 'type',
  BEFORE_DATE = 'before',
  AFTER_DATE = 'after',
}

export type SetDates = React.Dispatch<
  React.SetStateAction<{
    before: string;
    after: string;
  }>
>;
