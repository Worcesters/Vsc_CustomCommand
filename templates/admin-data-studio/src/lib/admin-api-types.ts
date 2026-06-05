export type RegistryEntry = {
  app_label: string;
  model_name: string;
  label: string;
  permissions: string[];
};

export type ModelRowsResponse = {
  results: Array<Record<string, string | number | boolean | null>>;
  count: number;
  pk_field?: string;
};

export type QueryResultRow = Record<string, string | number | boolean | null>;

export type QueryExecuteResponse = {
  columns: string[];
  rows: QueryResultRow[];
  row_count: number;
  truncated: boolean;
  elapsed_ms: number;
};
