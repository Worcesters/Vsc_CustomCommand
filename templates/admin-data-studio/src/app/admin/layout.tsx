import "@/styles/admin/admin.scss";
import "@/styles/admin/data-studio.scss";

export default function AdminLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return <div style={{ height: "100vh", overflow: "hidden" }}>{children}</div>;
}
