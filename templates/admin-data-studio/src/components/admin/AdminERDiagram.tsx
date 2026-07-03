"use client";

import { useCallback, useEffect, useMemo, useRef, useState } from "react";
import {
  Background,
  Controls,
  MarkerType,
  ReactFlow,
  ReactFlowProvider,
  type Edge,
  type Node,
  type NodeProps,
} from "@xyflow/react";
import "@xyflow/react/dist/style.css";
import dagre from "@dagrejs/dagre";
import { toSvg } from "html-to-image";
import { Download, FileCode, Key, LinkIcon, Maximize2, X } from "lucide-react";
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
    <div
      className={`ds-er-node nopan${isSelected ? " ds-er-node--selected" : ""}`}
    >
      <div className={headClass}>
        <span>{table.name}</span>
        <span style={{ float: "right", opacity: 0.85, fontSize: "0.75rem" }}>
          {table.schema}
        </span>
      </div>
      <div className="ds-er-node__body nowheel nodrag nopan">
        {table.columns.map((col) => (
          <div key={col.name} className="ds-er-node__col">
            {col.primaryKey ? <Key size={12} className="ds-icon--pk" /> : null}
            {col.foreignKey ? <LinkIcon size={12} className="ds-icon--fk" /> : null}
            <span className="ds-er-node__col-name">{col.name}</span>
            <span className="ds-er-node__col-type">{col.type}</span>
          </div>
        ))}
      </div>
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

type ErFlowSurfaceProps = Readonly<{
  nodes: Node<ErNodeData>[];
  edges: Edge[];
  className?: string;
  interactive?: boolean;
  showControls?: boolean;
  fitViewOnMount?: boolean;
  onNodeClick?: (_: React.MouseEvent, node: Node<ErNodeData>) => void;
  onOpenPreview?: () => void;
}>;

function ErFlowSurface({
  nodes,
  edges,
  className,
  interactive = true,
  showControls = true,
  fitViewOnMount = true,
  onNodeClick,
  onOpenPreview,
}: ErFlowSurfaceProps) {
  const preventContextMenu = useCallback((event: React.MouseEvent) => {
    event.preventDefault();
  }, []);

  const handlePaneClick = useCallback(() => {
    if (onOpenPreview) {
      onOpenPreview();
    }
  }, [onOpenPreview]);

  const handleNodeClick = useCallback(
    (event: React.MouseEvent, node: Node<ErNodeData>) => {
      if (onOpenPreview) {
        onOpenPreview();
        return;
      }
      onNodeClick?.(event, node);
    },
    [onNodeClick, onOpenPreview],
  );

  return (
    <ReactFlowProvider>
      <div
        className={className}
        onContextMenu={preventContextMenu}
      >
        <ReactFlow
          nodes={nodes}
          edges={edges}
          nodeTypes={nodeTypes}
          onNodeClick={handleNodeClick}
          onPaneClick={onOpenPreview ? handlePaneClick : undefined}
          nodesDraggable={interactive}
          nodesConnectable={false}
          elementsSelectable={interactive}
          selectNodesOnDrag={false}
          panOnDrag={[2]}
          panOnScroll={false}
          zoomOnScroll
          zoomOnPinch
          zoomOnDoubleClick={false}
          fitView={fitViewOnMount}
          minZoom={0.08}
          maxZoom={2.5}
          defaultViewport={{ x: 0, y: 0, zoom: 0.85 }}
          proOptions={{ hideAttribution: true }}
        >
          <Background gap={20} color="var(--ds-border)" />
          {showControls ? <Controls showInteractive={interactive} /> : null}
        </ReactFlow>
      </div>
    </ReactFlowProvider>
  );
}

type AdminERDiagramInnerProps = Readonly<{
  tables: StudioTable[];
  global: GlobalSchema;
  selectedTableId?: string;
  onTableSelect: (tableId: string) => void;
}>;

function AdminERDiagramInner({
  tables,
  global,
  selectedTableId,
  onTableSelect,
}: AdminERDiagramInnerProps) {
  const captureRef = useRef<HTMLDivElement>(null);
  const [previewOpen, setPreviewOpen] = useState(false);

  const { nodes, edges } = useMemo(() => {
    const flowNodes: Node<ErNodeData>[] = tables.map((table, i) => ({
      id: table.id,
      type: "erTable",
      position: { x: 0, y: 0 },
      dragHandle: ".ds-er-node",
      style: { width: NODE_W },
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

  const openPreview = useCallback(() => {
    setPreviewOpen(true);
  }, []);

  const closePreview = useCallback(() => {
    setPreviewOpen(false);
  }, []);

  useEffect(() => {
    if (!previewOpen) {
      return undefined;
    }
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") {
        setPreviewOpen(false);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [previewOpen]);

  const exportSvg = async () => {
    if (!captureRef.current) return;
    const dataUrl = await toSvg(captureRef.current, {
      cacheBust: true,
      backgroundColor: "#080808",
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
    <>
      <div style={{ display: "flex", flexDirection: "column", height: "100%" }}>
        <div className="ds-grid-toolbar">
          <span className="shell__muted">
            Clic droit : deplacer · Molette : zoom · Apercu (bas droite) : clic gauche
          </span>
          <div style={{ marginLeft: "auto", display: "flex", gap: "0.5rem" }}>
            <button
              type="button"
              className="ds-btn ds-btn--ghost"
              onClick={openPreview}
              title="Ouvrir l'apercu plein ecran"
            >
              <Maximize2 size={16} />
              Apercu
            </button>
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
        <div ref={captureRef} className="ds-er-capture" style={{ flex: 1, minHeight: 0, position: "relative" }}>
          <ErFlowSurface
            className="ds-er-capture__flow"
            nodes={nodes}
            edges={edges}
            onNodeClick={onNodeClick}
            showControls
            interactive
          />
          <div className="ds-er-preview" title="Clic gauche : ouvrir l'apercu · Clic droit : deplacer · Molette : zoom">
            <ErFlowSurface
              className="ds-er-preview__flow"
              nodes={nodes}
              edges={edges}
              onOpenPreview={openPreview}
              showControls={false}
              interactive={false}
              fitViewOnMount
            />
            <div className="ds-er-preview__label">
              <Maximize2 size={12} />
              Apercu
            </div>
          </div>
        </div>
      </div>

      {previewOpen ? (
        <div className="ds-er-modal" role="dialog" aria-modal="true" aria-label="Apercu du schema ER">
          <button
            type="button"
            className="ds-er-modal__backdrop"
            aria-label="Fermer l'apercu"
            onClick={closePreview}
          />
          <div className="ds-er-modal__panel">
            <header className="ds-er-modal__header">
              <div>
                <h3>Schema ER — apercu</h3>
                <p className="shell__muted ds-er-modal__hint">
                  Clic droit : deplacer · Molette : zoom · Echap pour fermer
                </p>
              </div>
              <button
                type="button"
                className="ds-btn ds-btn--ghost ds-btn--icon"
                aria-label="Fermer"
                onClick={closePreview}
              >
                <X size={18} />
              </button>
            </header>
            <div className="ds-er-modal__canvas">
              <ErFlowSurface
                className="ds-er-modal__flow"
                nodes={nodes}
                edges={edges}
                onNodeClick={onNodeClick}
                showControls
                interactive
              />
            </div>
          </div>
        </div>
      ) : null}
    </>
  );
}

type AdminERDiagramProps = Readonly<{
  tables: StudioTable[];
  global: GlobalSchema;
  selectedTableId?: string;
  onTableSelect: (tableId: string) => void;
}>;

export function AdminERDiagram(props: AdminERDiagramProps) {
  return <AdminERDiagramInner {...props} />;
}
