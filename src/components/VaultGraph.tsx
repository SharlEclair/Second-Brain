import React, { useEffect, useState, useRef } from 'react';
import ForceGraph2D from 'react-force-graph-2d';
import { Loader2 } from 'lucide-react';

interface GraphData {
  nodes: { id: string; group: number; val: number; category: string }[];
  links: { source: string; target: string }[];
}

interface VaultGraphProps {
  onSelectNote: (noteName: string) => void;
}

const CATEGORY_COLORS: Record<string, string> = {
  'Recipe': '#10b981',      // Emerald Green
  'Job-Career': '#3b82f6',  // Blue
  'Job/Career': '#3b82f6',  // Blue
  'Spot to Visit': '#eab308', // Yellow
  'Event': '#ec4899',       // Pink
  'General': '#f97316',     // Orange
  'Reference': '#64748b',   // Slate Gray
};

export default function VaultGraph({ onSelectNote }: VaultGraphProps) {
  const [data, setData] = useState<GraphData | null>(null);
  const [loading, setLoading] = useState(true);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetchGraphData();

    if (!containerRef.current) return;
    
    const observer = new ResizeObserver((entries) => {
      for (let entry of entries) {
        setDimensions({
          width: entry.contentRect.width,
          height: entry.contentRect.height
        });
      }
    });
    
    observer.observe(containerRef.current);
    
    return () => observer.disconnect();
  }, []);

  const fetchGraphData = async () => {
    try {
      const res = await fetch('/api/graph');
      const json = await res.json();
      setData(json);
    } catch (e) {
      console.error('Failed to fetch graph data', e);
    } finally {
      setData(prev => prev || { nodes: [], links: [] });
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="w-full h-[320px] flex items-center justify-center bg-black border border-slate-800 rounded-sm">
        <Loader2 className="w-6 h-6 text-orange-500 animate-spin" />
      </div>
    );
  }

  if (!data || data.nodes.length === 0) {
    return (
      <div className="w-full h-[320px] flex items-center justify-center bg-black border border-slate-800 rounded-sm text-slate-500 font-mono text-xs">
        No connections found in vault.
      </div>
    );
  }

  const getNodeColor = (node: any) => {
    return CATEGORY_COLORS[node.category] || '#a855f7'; // Purple default
  };

  return (
    <div ref={containerRef} className="w-full h-[320px] bg-black border border-slate-800 rounded-sm overflow-hidden relative">
      <div className="absolute top-4 left-4 z-10 text-[9px] text-slate-400 font-mono uppercase bg-black/85 px-2 py-1 rounded-sm border border-slate-850 flex items-center gap-2">
        <span className="w-1.5 h-1.5 rounded-full bg-orange-500 animate-pulse"></span>
        Knowledge Network ({data.nodes.length} nodes)
      </div>
      
      {/* Legend */}
      <div className="absolute bottom-4 right-4 z-10 text-[9px] font-mono bg-black/85 p-2 rounded-sm border border-slate-850 max-h-[120px] overflow-y-auto space-y-1 select-none">
        {Object.entries(CATEGORY_COLORS).map(([cat, color]) => (
          <div key={cat} className="flex items-center gap-1.5">
            <span className="w-2 h-2 rounded-full" style={{ backgroundColor: color }}></span>
            <span className="text-slate-400 text-[8px] uppercase">{cat}</span>
          </div>
        ))}
      </div>

      <ForceGraph2D
        width={dimensions.width}
        height={dimensions.height}
        graphData={data}
        nodeLabel="id"
        nodeColor={getNodeColor}
        linkColor={() => 'rgba(255, 255, 255, 0.08)'}
        nodeRelSize={4}
        linkWidth={1.5}
        backgroundColor="#000000"
        onNodeClick={(node: any) => {
          if (node && node.id) {
            onSelectNote(node.id);
          }
        }}
      />
    </div>
  );
}
