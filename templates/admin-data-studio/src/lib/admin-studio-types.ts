export type StudioColumn = {
  name: string;
  type: string;
  nullable: boolean;
  primaryKey: boolean;
  editable?: boolean;
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

export type StudioRow = Record<string, string | number | boolean | null>;

export type StudioView = "data" | "structure" | "diagram";
