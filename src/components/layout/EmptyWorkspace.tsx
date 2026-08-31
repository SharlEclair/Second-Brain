import React from 'react';
import { Brain, Sparkles, Loader2, Plus, Zap, Clock, Shield, Search } from 'lucide-react';
import { motion } from 'motion/react';
import { Note } from '../../types';
import VaultGraph from '../VaultGraph';
import InboxCompileWidget from '../InboxCompileWidget';
import { LibraryDirectory } from '../LibraryDirectory';
import SerendipityWidget from '../SerendipityWidget';
import EventsWidget from '../EventsWidget';
import SuggestionsWidget from '../SuggestionsWidget';
import ActivityHeatmap from '../ActivityHeatmap';

interface EmptyWorkspaceProps {
  notes: Note[];
  loadingNote: boolean;
  onSelectNote: (note: Note) => void;
  onSelectNoteByName: (name: string) => void;
  onCompileComplete: () => void;
  onGenerateWeeklyBrief: () => void;
}

export const EmptyWorkspace: React.FC<EmptyWorkspaceProps> = ({
  notes,
  loadingNote,
  onSelectNote,
  onSelectNoteByName,
  onCompileComplete,
  onGenerateWeeklyBrief,
}) => {
  return (
    <motion.div
      key="empty"
      initial={{ opacity: 0, y: 10 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, scale: 0.95 }}
      className="h-full flex flex-col items-center justify-center w-full"
    >
      <div className="w-full h-full overflow-y-auto py-12 flex flex-col items-center">
        {/* Idle Hero Graphic */}
        <div className="flex flex-col items-center justify-center text-center max-w-md mx-auto mb-12 shrink-0">
          <div className="w-20 h-20 bg-black border border-slate-800 flex items-center justify-center mb-6 relative">
            <Brain className="w-8 h-8 text-orange-500" />
          </div>
          <h2 className="text-2xl font-display font-light italic mb-3 tracking-tight text-white">
            Awaiting Input
          </h2>
          <p className="text-xs text-slate-500 leading-relaxed mb-8 uppercase tracking-widest">
            SYSTEM IDLE. INGEST URL OR SELECT EXISTING ENTRY.
          </p>
        </div>

        {/* Vault Graph 2D */}
        <div className="w-full max-w-5xl mx-auto px-8 mb-6">
          <VaultGraph onSelectNote={onSelectNoteByName} />
        </div>

        {/* 4-Column Widget Grid */}
        <div className="w-full max-w-5xl mx-auto px-8 grid grid-cols-1 md:grid-cols-4 gap-6">
          <div className="md:col-span-1 space-y-6">
            <InboxCompileWidget onCompileComplete={onCompileComplete} />
            <LibraryDirectory onSelectCategory={onSelectNoteByName} />
            <SerendipityWidget onSelectNote={onSelectNote} />
            <EventsWidget onSelectEvent={onSelectNote} />

            <div className="bg-[#0a0a0a] border border-slate-800 p-4 rounded-sm space-y-3">
              <div className="flex items-center gap-2">
                <Sparkles className="w-4 h-4 text-indigo-400 animate-pulse" />
                <h4 className="text-[10px] font-mono uppercase tracking-widest text-slate-300">
                  Weekly Intelligence
                </h4>
              </div>
              <p className="text-[10px] text-slate-500 font-mono leading-relaxed">
                Aggregate notes and learning materials ingested over the past 7 days into a
                structured weekly brief.
              </p>
              <button
                onClick={onGenerateWeeklyBrief}
                disabled={loadingNote}
                className="w-full py-2 bg-indigo-500/10 border border-indigo-500/30 hover:border-indigo-500 text-indigo-400 hover:text-white font-mono text-[10px] uppercase tracking-wider transition-all rounded-sm flex items-center justify-center gap-2 cursor-pointer disabled:opacity-50"
              >
                {loadingNote ? (
                  <Loader2 className="w-3 h-3 animate-spin" />
                ) : (
                  <Plus className="w-3.5 h-3.5" />
                )}
                Generate Weekly Brief
              </button>
            </div>
          </div>

          <div className="md:col-span-3 space-y-6">
            <SuggestionsWidget onSelectSuggestion={onSelectNote} />
            <ActivityHeatmap notes={notes} />

            <div className="grid grid-cols-2 md:grid-cols-4 gap-3 w-full mt-6">
              {[
                {
                  icon: <Zap className="w-4 h-4 text-orange-500" />,
                  label: 'Auto Transcribe',
                },
                {
                  icon: <Clock className="w-4 h-4 text-slate-400" />,
                  label: 'Long-term Recall',
                },
                {
                  icon: <Shield className="w-4 h-4 text-emerald-500" />,
                  label: 'Secure Storage',
                },
                {
                  icon: <Search className="w-4 h-4 text-blue-400" />,
                  label: 'AI Search',
                },
              ].map((feat, i) => (
                <div
                  key={i}
                  className="flex flex-col items-center gap-2 p-4 bg-[#111] border border-slate-800 hover:border-slate-700 transition-colors rounded-sm group"
                >
                  {feat.icon}
                  <span className="text-[10px] uppercase font-mono text-slate-500 group-hover:text-slate-400 transition-colors">
                    {feat.label}
                  </span>
                </div>
              ))}
            </div>
          </div>
        </div>
      </div>
    </motion.div>
  );
};
