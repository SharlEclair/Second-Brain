import React, { useEffect, useState, useRef } from 'react';
import ForceGraph2D from 'react-force-graph-2d';
import { Loader2 } from 'lucide-react';

interface GraphData {
  nodes: { id: string; group: number }[];
  links: { source: string; target: string }[];
}

export default function VaultGraph() {
  const [data, setData] = useState<GraphData | null>(null);
  const [loading, setLoading] = useState(true);
  const [dimensions, setDimensions] = useState({ width: 0, height: 0 });
  const containerRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetchGraphData();

    const updateDimensions = () => {
      if (containerRef.current) {
        setDimensions({
          width: containerRef.current.clientWidth,
          height: containerRef.current.clientHeight
        });
      }
    };

    updateDimensions();
    window.addEventListener('resize', updateDimensions);
    return () => window.removeEventListener('resize', updateDimensions);
  }, []);

  const fetchGraphData = async () => {
    try {
      const res = await fetch('/api/graph');
      const json = await res.json();
      setData(json);
    } catch (e) {
      console.error('Failed to fetch graph data', e);
    } finally {
      setLoading(false);
    }
  };

  if (loading) {
    return (
      <div className="w-full h-[500px] flex items-center justify-center bg-black border border-slate-800 rounded-sm">
        <Loader2 className="w-6 h-6 text-orange-500 animate-spin" />
      </div>
    );
  }

  if (!data || data.nodes.length === 0) {
    return (
      <div className="w-full h-[500px] flex items-center justify-center bg-black border border-slate-800 rounded-sm text-slate-500 font-mono text-sm">
        No connections found in vault.
      </div>
    );
  }

  return (
    <div ref={containerRef} className="w-full h-[500px] bg-black border border-slate-800 rounded-sm overflow-hidden relative">
      <div className="absolute top-4 left-4 z-10 text-[10px] text-slate-400 font-mono uppercase bg-black/80 px-2 py-1 rounded-sm border border-slate-800">
        Knowledge Network ({data.nodes.length} nodes)
      </div>
      <ForceGraph2D
        width={dimensions.width}
        height={dimensions.height}
        graphData={data}
        nodeLabel="id"
        nodeColor={(node: any) => node.group === 1 ? '#f97316' : '#3b82f6'}
        linkColor={() => 'rgba(255, 255, 255, 0.1)'}
        nodeRelSize={4}
        linkWidth={1}
        backgroundColor="#000000"
      />
    </div>
  );
}
