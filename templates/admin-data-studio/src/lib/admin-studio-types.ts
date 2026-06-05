export type StudioColumn = {
  name: string;
  type: string;
  nullable: boolean;
  primaryKey: boolean;
  editable?: boolean;
  blank?: boolean;
  required?: boolean;
  requiredOnCreate?: boolean;
  autoIncrement?: boolean;
  foreignKey?: { table: string; column: string; targetId: string };
  defaultValue?: string | number | boolean;
};

export type StudioTable = {
  id: string;
  name: string;
  schema: string;
  appLabel: string;
  modelName: string;
  columns: StudioColumn[];
  rowCount: number;
};

export type StudioRow = Record<string, string | number | boolean | null> & {
  password_set?: boolean;
};

export type StudioView = "data" | "structure" | "diagram";

export type StudioMode = "explorer" | "query";
