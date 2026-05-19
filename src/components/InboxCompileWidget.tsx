import React, { useState, useEffect } from 'react';
import { Inbox, Layers, Loader2, Sparkles, AlertCircle, CheckCircle } from 'lucide-react';

interface InboxCompileWidgetProps {
  onCompileComplete: () => void;
}

const InboxCompileWidget: React.FC<InboxCompileWidgetProps> = ({ onCompileComplete }) => {
  const [inboxMode, setInboxMode] = useState<boolean>(false);
  const [pendingCount, setPendingCount] = useState<number>(0);
  const [isCompiling, setIsCompiling] = useState<boolean>(false);
  const [compileStatus, setCompileStatus] = useState<string>('');
  const [error, setError] = useState<string | null>(null);
  const [successMsg, setSuccessMsg] = useState<string | null>(null);

  const fetchStatus = async () => {
    try {
      const res = await fetch('/api/config');
      if (res.ok) {
        const data = await res.json();
        setInboxMode(data.inbox_mode || false);
      }

      const pendingRes = await fetch('/api/inbox/pending');
      if (pendingRes.ok) {
        const pendingData = await pendingRes.json();
        setPendingCount(pendingData.count || 0);
      }
    } catch (err) {
      console.error('Failed to fetch inbox/config status:', err);
    }
  };

  useEffect(() => {
    fetchStatus();
    const interval = setInterval(fetchStatus, 5000);
    return () => clearInterval(interval);
  }, []);

  const handleToggleInboxMode = async () => {
    const nextMode = !inboxMode;
    try {
      setError(null);
      const res = await fetch('/api/config/inbox_mode', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ inbox_mode: nextMode })
      });
      if (res.ok) {
        setInboxMode(nextMode);
      } else {
        setError('Failed to update inbox mode');
      }
    } catch (err: any) {
      setError(err.message || 'Error updating inbox mode');
    }
  };

  const handleCompile = async () => {
    setIsCompiling(true);
    setCompileStatus('Analyzing raw clippings...');
    setError(null);
    setSuccessMsg(null);
    try {
      const res = await fetch('/api/compile', { method: 'POST' });
      const data = await res.json();
      if (res.ok && data.status === 'success') {
        setCompileStatus('Formatting wiki notes...');
        await new Promise((resolve) => setTimeout(resolve, 800));
        setCompileStatus('Updating vector index...');
        await new Promise((resolve) => setTimeout(resolve, 600));
        
        setSuccessMsg(`Compiled ${data.compiled_count} items!`);
        setPendingCount(0);
        onCompileComplete();
      } else {
        setError(data.detail || 'Compilation failed');
      }
    } catch (err: any) {
      setError(err.message || 'Error occurred during compilation');
    } finally {
      setIsCompiling(false);
      setCompileStatus('');
    }
  };

  return (
    <div className="bg-[#0a0a0a] border border-slate-800 p-4 rounded-sm space-y-4 hover:border-slate-700 transition-all relative overflow-hidden group">
      {/* Visual background gradient accent */}
      <div className="absolute top-0 right-0 w-32 h-32 bg-indigo-500/5 rounded-full blur-3xl pointer-events-none group-hover:bg-indigo-500/10 transition-all duration-500" />
      
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-2">
          <Inbox className={`w-4 h-4 ${inboxMode ? 'text-indigo-400' : 'text-slate-500'}`} />
          <h4 className="text-[10px] font-mono uppercase tracking-widest text-slate-300">Librarian Inbox</h4>
        </div>
        
        {/* Toggle switch */}
        <label className="relative inline-flex items-center cursor-pointer select-none">
          <input 
            type="checkbox" 
            checked={inboxMode} 
            onChange={handleToggleInboxMode}
            className="sr-only peer"
          />
          <div className="w-8 h-4 bg-slate-800 rounded-full peer peer-focus:ring-0 peer-checked:after:translate-x-full after:content-[''] after:absolute after:top-0.5 after:left-[2px] after:bg-slate-400 peer-checked:after:bg-indigo-400 after:border-none after:rounded-full after:h-3 after:w-3.5 after:transition-all peer-checked:bg-indigo-950/50 border border-slate-700 transition-colors" />
          <span className="text-[8px] font-mono text-slate-500 ml-1.5 uppercase tracking-wider font-bold">
            {inboxMode ? 'Raw Mode' : 'Direct'}
          </span>
        </label>
      </div>

      <div className="space-y-3 relative z-10">
        <p className="text-[10px] text-slate-500 font-mono leading-relaxed">
          {inboxMode 
            ? 'Ingested clippings are sent to the raw inbox. Compile them to trigger AI categorization and wiki link injection.' 
            : 'Clippings are automatically categorized and sorted in real-time by the AI Librarian.'}
        </p>

        {/* Status display */}
        {pendingCount > 0 && (
          <div className="p-2 bg-indigo-500/5 border border-indigo-500/20 rounded-sm flex items-center justify-between animate-pulse">
            <div className="flex items-center gap-2">
              <Layers className="w-3.5 h-3.5 text-indigo-400" />
              <span className="text-[10px] font-mono text-indigo-300 font-bold uppercase">
                {pendingCount} Clippings Pending
              </span>
            </div>
            <span className="text-[8px] font-mono bg-indigo-500/10 px-1.5 py-0.5 text-indigo-400 rounded-sm font-bold uppercase">
              Action Required
            </span>
          </div>
        )}

        {isCompiling && (
          <div className="p-2 bg-black/40 border border-slate-800 rounded-sm flex items-center gap-2">
            <Loader2 className="w-3.5 h-3.5 text-indigo-400 animate-spin" />
            <span className="text-[10px] font-mono text-slate-400 uppercase">
              {compileStatus}
            </span>
          </div>
        )}

        {error && (
          <div className="p-2 bg-red-950/10 border border-red-500/20 rounded-sm flex items-center gap-2 text-red-400 font-mono text-[9px]">
            <AlertCircle className="w-3.5 h-3.5 shrink-0" />
            <span className="truncate">{error}</span>
          </div>
        )}

        {successMsg && (
          <div className="p-2 bg-emerald-950/10 border border-emerald-500/20 rounded-sm flex items-center gap-2 text-emerald-400 font-mono text-[9px] animate-in fade-in">
            <CheckCircle className="w-3.5 h-3.5 shrink-0" />
            <span>{successMsg}</span>
          </div>
        )}

        {/* Compile button */}
        {inboxMode && (
          <button
            onClick={handleCompile}
            disabled={pendingCount === 0 || isCompiling}
            className={`w-full py-2 font-mono text-[10px] uppercase tracking-wider transition-all rounded-sm flex items-center justify-center gap-2 border ${
              pendingCount > 0 && !isCompiling
                ? 'bg-indigo-500/10 border-indigo-500/30 hover:border-indigo-500 text-indigo-400 hover:text-white cursor-pointer shadow-[0_0_10px_rgba(99,102,241,0.05)]'
                : 'bg-[#111] border-slate-800 text-slate-600 cursor-not-allowed'
            }`}
          >
            {isCompiling ? (
              <Loader2 className="w-3.5 h-3.5 animate-spin" />
            ) : (
              <Sparkles className="w-3.5 h-3.5" />
            )}
            Compile Raw Inbox
          </button>
        )}
      </div>
    </div>
  );
};

export default InboxCompileWidget;
