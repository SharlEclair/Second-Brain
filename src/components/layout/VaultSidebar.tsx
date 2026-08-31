import React from 'react';
import { Brain, Search, RefreshCw, FileText, Shield } from 'lucide-react';
import { format } from 'date-fns';
import { Note } from '../../types';
import { cn } from '../../lib/utils';

interface VaultSidebarProps {
  notes: Note[];
  selectedNote: Note | null;
  searchQuery: string;
  isSyncing: boolean;
  onSearchChange: (query: string) => void;
  onSelectNote: (note: Note) => void;
  onSync: () => void;
}

export const VaultSidebar: React.FC<VaultSidebarProps> = ({
  notes,
  selectedNote,
  searchQuery,
  isSyncing,
  onSearchChange,
  onSelectNote,
  onSync,
}) => {
  const filteredNotes = notes.filter(
    (n) => !searchQuery || n.title.toLowerCase().includes(searchQuery.toLowerCase())
  );

  return (
    <aside className="w-80 flex flex-col border-r border-slate-800 bg-[#111]">
      {/* Top Header */}
      <div className="p-6 border-b border-slate-800 flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="w-8 h-8 rounded-sm bg-orange-500/10 flex items-center justify-center border border-orange-500/20">
            <Brain className="w-5 h-5 text-orange-500" />
          </div>
          <h1 className="font-display font-light italic text-xl tracking-tight text-white glow-text">
            BRAIN_VAULT
          </h1>
        </div>
        <button
          onClick={onSync}
          disabled={isSyncing}
          className="flex items-center gap-2 px-3 py-1.5 text-xs font-bold uppercase tracking-widest text-slate-500 hover:text-white transition-all rounded-md hover:bg-white/5 cursor-pointer disabled:opacity-50"
        >
          <RefreshCw className={cn('w-4 h-4', isSyncing && 'animate-spin')} />
          Sync Vault
        </button>
      </div>

      {/* Note Search and List */}
      <div className="flex-1 overflow-y-auto p-4 space-y-2">
        <div className="text-[10px] uppercase tracking-widest font-bold text-slate-500 px-3 border-b border-slate-800 pb-2 mb-4">
          Stored Knowledge ({notes.length})
        </div>
        <div className="px-1 mb-3">
          <div className="relative">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-600" />
            <input
              type="text"
              placeholder="Search notes..."
              value={searchQuery}
              onChange={(e) => onSearchChange(e.target.value)}
              className="w-full bg-black border border-slate-800 rounded-sm py-2 pl-9 pr-3 text-xs focus:outline-none focus:ring-1 focus:ring-orange-500/50 transition-all font-mono placeholder-slate-700 text-slate-300"
            />
          </div>
        </div>
        {notes.length === 0 && (
          <div className="px-3 py-6 text-sm text-slate-500 italic">No notes ingested yet.</div>
        )}
        {filteredNotes.map((note) => (
          <button
            key={note.fileName}
            onClick={() => onSelectNote(note)}
            className={cn(
              'w-full text-left p-3 rounded-sm border transition-all group flex items-start gap-3 cursor-pointer',
              selectedNote?.fileName === note.fileName
                ? 'bg-[#111] border-l-2 border-l-orange-500 border-y-slate-800 border-r-slate-800 text-slate-300'
                : 'bg-transparent border-transparent text-slate-500 hover:bg-slate-800/50'
            )}
          >
            <FileText
              className={cn(
                'w-4 h-4 mt-0.5 shrink-0',
                selectedNote?.fileName === note.fileName ? 'text-orange-500' : 'opacity-50'
              )}
            />
            <div className="flex-1 min-w-0">
              <div className="text-sm font-medium truncate">{note.title}</div>
              <div className="text-[10px] opacity-60 font-mono mt-1">
                {format(new Date(note.date), 'yyyy-MM-dd HH:mm')}
              </div>
            </div>
          </button>
        ))}
      </div>

      {/* Footer Node Badge */}
      <div className="p-4 border-t border-slate-800 bg-[#111]">
        <div className="flex items-center gap-3 px-3 py-3 rounded-sm bg-black border border-slate-800">
          <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center">
            <Shield className="w-4 h-4 text-emerald-500" />
          </div>
          <div className="flex-1 truncate">
            <div className="text-[10px] text-slate-500 uppercase tracking-widest leading-none mb-1">
              Secure Node
            </div>
            <div className="text-xs font-mono text-emerald-500 truncate">V_SYNCED</div>
          </div>
        </div>
      </div>
    </aside>
  );
};
