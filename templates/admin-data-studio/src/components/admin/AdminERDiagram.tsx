"use client";

import { useCallback, useMemo, useRef } from "react";
import {
  Background,
  Controls,
  Handle,
  MarkerType,
  MiniMap,
  Position,
  ReactFlow,
  ReactFlowProvider,
  type Edge,
  type Node,
  type NodeProps,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import dagre from "@dagrejs/dagre";
import { toSvg } from "html-to-image";
import { Download, FileCode, Key, LinkIcon } from "lucide-react";
import { downloadSchemaMermaid } from "@/lib/admin-api-client";
import type { GlobalSchema } from "@/lib/schema-types";
import type { StudioTable } from "@/lib/admin-studio-types";

const NODE_W = 280;
const NODE_H = 200;

type ErNodeData = {
  table: StudioTable;
  colorIndex: number;
  isSelected: boolean;
};

function ErTableNode({ data }: NodeProps<Node<ErNodeData>>) {
  const { table, colorIndex, isSelected } = data;
  const headClass = `ds-er-node__head ds-er-node__head--c${colorIndex % 3}`;
  return (
    <div className={`ds-er-node${isSelected ? " ds-er-node--selected" : ""}`}>
      <Handle type="target" position={Position.Left} />
      <div className={headClass}>
        <span>{table.name}</span>
        <span style={{ float: "right", opacity: 0.85, fontSize: "0.75rem" }}>
          {table.schema}
        </span>
      </div>
      <div className="ds-er-node__body">
        {table.columns.slice(0, 8).map((col) => (
          <div key={col.name} className="ds-er-node__col">
            {col.primaryKey ? <Key size={12} color="#eab308" /> : null}
            {col.foreignKey ? <LinkIcon size={12} color="#60a5fa" /> : null}
            <span className="ds-er-node__col-name">{col.name}</span>
            <span className="ds-er-node__col-type">{col.type}</span>
          </div>
        ))}
        {table.columns.length > 8 ? (
          <div className="ds-er-node__col" style={{ justifyContent: "center" }}>
            +{table.columns.length - 8} colonnes
          </div>
        ) : null}
      </div>
      <Handle type="source" position={Position.Right} />
    </div>
  );
}

const nodeTypes = { erTable: ErTableNode };

function layoutElements(
  nodes: Node<ErNodeData>[],
  edges: Edge[],
): { nodes: Node<ErNodeData>[]; edges: Edge[] } {
  const g = new dagre.graphlib.Graph();
  g.setDefaultEdgeLabel(() => ({}));
  g.setGraph({ rankdir: "LR", nodesep: 80, ranksep: 120 });
  nodes.forEach((n) => g.setNode(n.id, { width: NODE_W, height: NODE_H }));
  edges.forEach((e) => g.setEdge(e.source, e.target));
  dagre.layout(g);
  const laid = nodes.map((node) => {
    const pos = g.node(node.id);
    return {
      ...node,
      position: { x: pos.x - NODE_W / 2, y: pos.y - NODE_H / 2 },
    };
  });
  return { nodes: laid, edges };
}

type AdminERDiagramInnerProps = {
  tables: StudioTable[];
  global: GlobalSchema;
  selectedTableId?: string;
  onTableSelect: (tableId: string) => void;
};

function AdminERDiagramInner({
  tables,
  global,
  selectedTableId,
  onTableSelect,
}: AdminERDiagramInnerProps) {
  const captureRef = useRef<HTMLDivElement>(null);

  const { nodes, edges } = useMemo(() => {
    const flowNodes: Node<ErNodeData>[] = tables.map((table, i) => ({
      id: table.id,
      type: "erTable",
      position: { x: 0, y: 0 },
      data: {
        table,
        colorIndex: i,
        isSelected: table.id === selectedTableId,
      },
    }));
    const flowEdges: Edge[] = (global.edges ?? []).map((edge, idx) => ({
      id: `e-${idx}`,
      source: edge.from,
      target: edge.to,
      label: `${edge.field} (${edge.type})`,
      type: "smoothstep",
      animated: edge.type === "M2M",
      markerEnd: { type: MarkerType.ArrowClosed },
      style: { stroke: "var(--ds-primary)" },
      labelStyle: { fill: "var(--ds-muted)", fontSize: 10 },
    }));
    return layoutElements(flowNodes, flowEdges);
  }, [tables, global.edges, selectedTableId]);

  const onNodeClick = useCallback(
    (_: React.MouseEvent, node: Node<ErNodeData>) => {
      onTableSelect(node.id);
    },
    [onTableSelect],
  );

  const exportSvg = async () => {
    if (!captureRef.current) return;
    const dataUrl = await toSvg(captureRef.current, {
      cacheBust: true,
      backgroundColor: "#0f1117",
    });
    const anchor = document.createElement("a");
    anchor.href = dataUrl;
    anchor.download = "schema-er-diagram.svg";
    anchor.click();
  };

  const exportMermaid = async () => {
    try {
      await downloadSchemaMermaid();
    } catch (err) {
      alert(err instanceof Error ? err.message : "Export Mermaid impossible");
    }
  };

  if (tables.length === 0) {
    return (
      <div className="data-studio__empty">
        <p>Aucune table dans le registry.</p>
      </div>
    );
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
      <div className="ds-grid-toolbar">
        <span className="shell__muted">Cliquez sur une table pour naviguer</span>
        <div style={{ marginLeft: "auto", display: "flex", gap: "0.5rem" }}>
          <button type="button" className="ds-btn ds-btn--ghost" onClick={() => void exportMermaid()}>
            <FileCode size={16} />
            Mermaid (.mmd)
          </button>
          <button type="button" className="ds-btn ds-btn--primary" onClick={() => void exportSvg()}>
            <Download size={16} />
            SVG
          </button>
        </div>
      </div>
      <div ref={captureRef} className="ds-er-capture" style={{ flex: 1, minHeight: 0 }}>
        <ReactFlow
          nodes={nodes}
          edges={edges}
          nodeTypes={nodeTypes}
          onNodeClick={onNodeClick}
          fitView
          minZoom={0.25}
          maxZoom={1.5}
          defaultViewport={{ x: 0, y: 0, zoom: 0.85 }}
          proOptions={{ hideAttribution: true }}
        >
          <Background gap={20} color="var(--ds-border)" />
          <Controls />
          <MiniMap pannable zoomable />
        </ReactFlow>
      </div>
    </div>
  );
}

type AdminERDiagramProps = {
  tables: StudioTable[];
  global: GlobalSchema;
  selectedTableId?: string;
  onTableSelect: (tableId: string) => void;
};

export function AdminERDiagram(props: AdminERDiagramProps) {
  return (
    <ReactFlowProvider>
      <AdminERDiagramInner {...props} />
    </ReactFlowProvider>
  );
}
