import React, { useEffect, useState } from 'react';
import { Sparkles, Clock, Check, BookOpen, ChevronRight, RefreshCw, Loader2 } from 'lucide-react';

interface SerendipityNote {
  title: string;
  fileName: string;
  date: string;
  summary: string;
  last_reviewed: string | null;
}

interface SerendipityWidgetProps {
  onSelectNote: (note: any) => void;
}

export default function SerendipityWidget({ onSelectNote }: SerendipityWidgetProps) {
  const [notes, setNotes] = useState<SerendipityNote[]>([]);
  const [loading, setLoading] = useState(true);
  const [revealedIds, setRevealedIds] = useState<Record<string, boolean>>({});
  const [markingId, setMarkingId] = useState<string | null>(null);

  useEffect(() => {
    fetchSerendipity();
  }, []);

  const fetchSerendipity = async () => {
    setLoading(true);
    try {
      const res = await fetch('/api/serendipity');
      const data = await res.json();
      setNotes(data || []);
      setRevealedIds({});
    } catch (e) {
      console.error('Failed to fetch serendipity notes', e);
    } finally {
      setLoading(false);
    }
  };

  const toggleReveal = (fileName: string) => {
    setRevealedIds(prev => ({
      ...prev,
      [fileName]: !prev[fileName]
    }));
  };

  const handleMarkReviewed = async (e: React.MouseEvent, fileName: string) => {
    e.stopPropagation();
    setMarkingId(fileName);
    try {
      const res = await fetch('/api/notes/reviewed', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ fileName })
      });
      if (res.ok) {
        // Remove from list or refresh
        setTimeout(() => {
          setNotes(prev => prev.filter(n => n.fileName !== fileName));
          if (notes.length <= 1) {
            fetchSerendipity();
          }
        }, 300);
      }
    } catch (e) {
      console.error('Failed to mark note as reviewed', e);
    } finally {
      setMarkingId(null);
    }
  };

  if (loading) {
    return (
      <div className="bg-black border border-slate-800 rounded-sm overflow-hidden p-6 flex flex-col items-center justify-center min-h-[220px]">
        <Loader2 className="w-6 h-6 text-orange-500 animate-spin mb-2" />
        <span className="text-[10px] text-slate-500 uppercase tracking-widest font-mono">Loading Serendipity...</span>
      </div>
    );
  }

  if (notes.length === 0) {
    return (
      <div className="bg-black border border-slate-800 rounded-sm overflow-hidden p-6 text-center min-h-[220px] flex flex-col items-center justify-center">
        <Sparkles className="w-6 h-6 text-slate-600 mb-2" />
        <p className="text-xs text-slate-500 italic mb-4">No serendipitous notes found to review.</p>
        <button 
          onClick={fetchSerendipity}
          className="px-3 py-1.5 bg-slate-900 border border-slate-800 hover:border-slate-700 text-[10px] uppercase font-mono tracking-wider font-bold rounded-sm text-slate-300"
        >
          Check Again
        </button>
      </div>
    );
  }

  return (
    <div className="bg-black border border-slate-800 rounded-sm overflow-hidden">
      <div className="p-4 border-b border-slate-800 flex items-center justify-between bg-orange-500/5">
        <div className="flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-orange-500" />
          <h3 className="text-xs uppercase tracking-widest font-bold text-slate-300">Serendipity & Review</h3>
        </div>
        <button 
          onClick={fetchSerendipity} 
          className="flex items-center gap-1 text-[10px] text-slate-500 hover:text-white transition-colors"
          title="Refresh Serendipity"
        >
          <RefreshCw className="w-3 h-3" />
          <span>Refresh</span>
        </button>
      </div>
      
      <div className="p-4 space-y-4">
        {notes.slice(0, 1).map((note) => {
          const isRevealed = !!revealedIds[note.fileName];
          return (
            <div 
              key={note.fileName}
              className="border border-slate-800 bg-[#111] hover:border-slate-700 transition-all rounded-sm p-4 flex flex-col justify-between relative group overflow-hidden min-h-[180px]"
            >
              <div>
                <div className="flex items-center justify-between mb-2">
                  <span className="text-[9px] bg-orange-500/10 text-orange-400 border border-orange-500/20 px-2 py-0.5 rounded-sm font-mono uppercase">
                    Spaced Review
                  </span>
                  {note.last_reviewed && (
                    <span className="text-[9px] text-slate-600 font-mono">
                      Last: {new Date(note.last_reviewed).toLocaleDateString()}
                    </span>
                  )}
                </div>
                
                <h4 className="text-sm font-semibold text-white tracking-tight mb-3">
                  {note.title}
                </h4>

                {isRevealed ? (
                  <p className="text-xs text-slate-400 italic leading-relaxed mb-4 border-l border-orange-500/30 pl-3">
                    {note.summary || "No summary available for this note. Open the full note to read."}
                  </p>
                ) : (
                  <p className="text-xs text-slate-600 italic leading-relaxed mb-4">
                    Click "Reveal Summary" below to review key concepts or "Read Note" to open it.
                  </p>
                )}
              </div>

              <div className="flex items-center justify-between mt-4 pt-3 border-t border-slate-800/50">
                <div className="flex gap-2">
                  <button
                    onClick={() => toggleReveal(note.fileName)}
                    className="px-2.5 py-1 bg-slate-900 border border-slate-800 hover:border-slate-700 text-[10px] uppercase font-mono tracking-wider font-bold rounded-sm text-slate-400 hover:text-white transition-colors"
                  >
                    {isRevealed ? "Hide Summary" : "Reveal Summary"}
                  </button>
                  <button
                    onClick={() => onSelectNote(note)}
                    className="px-2.5 py-1 bg-orange-500 text-black hover:bg-orange-400 text-[10px] uppercase font-mono tracking-wider font-bold rounded-sm flex items-center gap-1 transition-colors"
                  >
                    <BookOpen className="w-3 h-3" />
                    <span>Read Note</span>
                  </button>
                </div>

                <button
                  onClick={(e) => handleMarkReviewed(e, note.fileName)}
                  disabled={markingId === note.fileName}
                  className="p-1.5 bg-emerald-500/10 border border-emerald-500/20 hover:bg-emerald-500/20 hover:border-emerald-500/40 text-emerald-400 rounded-sm flex items-center justify-center transition-colors disabled:opacity-50"
                  title="Mark as Reviewed"
                >
                  {markingId === note.fileName ? (
                    <Loader2 className="w-3.5 h-3.5 animate-spin text-emerald-400" />
                  ) : (
                    <Check className="w-3.5 h-3.5" />
                  )}
                </button>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
