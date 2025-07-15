export enum SeletableOptions {
  EXISTING,
  EMPTY,
  CUSTOM,
}

export interface Dataclip {
  id: string;
  name: string | null;
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

export const DataclipTypeNames: Record<string, string> = {
  http_request: 'http request',
  global: 'global',
  step_result: 'step result',
  saved_input: 'saved input',
  kafka: 'kafka message',
};

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
