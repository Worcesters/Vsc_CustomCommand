import type { Metadata } from "next";
import { AdminErrorState } from "@/components/admin/AdminErrorState";

export const metadata: Metadata = {
  title: "Administration indisponible",
  robots: { index: false },
};

export default function AdminUnavailablePage() {
  return <AdminErrorState />;
}
