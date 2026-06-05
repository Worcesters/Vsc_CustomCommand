export type ApiFieldErrors = Record<string, string>;

export class AdminApiClientError extends Error {
  readonly status: number;
  readonly fields: ApiFieldErrors;

  constructor(message: string, status: number, fields: ApiFieldErrors = {}) {
    super(message);
    this.name = "AdminApiClientError";
    this.status = status;
    this.fields = fields;
  }
}

export async function throwAdminApiError(
  res: Response,
  label: string,
): Promise<never> {
  const text = await res.text().catch(() => "");
  let detail = `${label} (HTTP ${res.status})`;
  let fields: ApiFieldErrors = {};

  if (text) {
    try {
      const json = JSON.parse(text) as {
        detail?: string;
        fields?: ApiFieldErrors;
      };
      if (json.detail) {
        detail = json.detail;
      }
      if (json.fields && typeof json.fields === "object") {
        fields = json.fields;
      }
    } catch {
      detail = text.slice(0, 400);
    }
  }

  throw new AdminApiClientError(detail, res.status, fields);
}
