import React from 'react';
import {
  Sparkles,
  Zap,
  CheckSquare,
  Brain,
  Copy,
  Check,
  X,
  Loader2,
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import ReactMarkdown from 'react-markdown';
import { Note, ActionResult, NoteActionType } from '../../types';

interface NoteViewerProps {
  selectedNote: Note;
  noteContent: string | null;
  actionLoading: string | null;
  actionResult: ActionResult | null;
  copied: boolean;
  onAction: (type: NoteActionType) => void;
  onDiscuss: () => void;
  onCopy: (text: string) => void;
  onClose: () => void;
  onSaveTasks: (tasksContent: string) => void;
  onDismissActionResult: () => void;
}

export const NoteViewer: React.FC<NoteViewerProps> = ({
  selectedNote,
  noteContent,
  actionLoading,
  actionResult,
  copied,
  onAction,
  onDiscuss,
  onCopy,
  onClose,
  onSaveTasks,
  onDismissActionResult,
}) => {
  return (
    <motion.div
      key={selectedNote.fileName}
      initial={{ opacity: 0 }}
      animate={{ opacity: 1 }}
      exit={{ opacity: 0 }}
      className="h-full flex flex-col"
    >
      {/* Action Toolbar */}
      <div className="flex items-center justify-between px-6 py-3 border-b border-slate-800 bg-black/50 sticky top-0 z-10 backdrop-blur-md">
        <div className="flex items-center gap-2">
          <button
            onClick={() => onAction('summarize')}
            disabled={!!actionLoading}
            className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all disabled:opacity-50 cursor-pointer"
          >
            {actionLoading === 'summarize' ? (
              <Loader2 className="w-3 h-3 animate-spin" />
            ) : (
              <Sparkles className="w-3 h-3 text-orange-500" />
            )}
            Summarize
          </button>
          <button
            onClick={() => onAction('deep_dive')}
            disabled={!!actionLoading}
            className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all disabled:opacity-50 cursor-pointer"
          >
            {actionLoading === 'deep_dive' ? (
              <Loader2 className="w-3 h-3 animate-spin" />
            ) : (
              <Zap className="w-3 h-3 text-orange-500" />
            )}
            Deep Dive
          </button>
          <button
            onClick={() => onAction('extract_tasks')}
            disabled={!!actionLoading}
            className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all disabled:opacity-50 cursor-pointer"
          >
            {actionLoading === 'extract_tasks' ? (
              <Loader2 className="w-3 h-3 animate-spin" />
            ) : (
              <CheckSquare className="w-3 h-3 text-orange-500" />
            )}
            Extract Tasks
          </button>
          <button
            onClick={onDiscuss}
            className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all cursor-pointer"
          >
            <Brain className="w-3 h-3 text-orange-500 animate-pulse" />
            Discuss
          </button>
        </div>

        <div className="flex items-center gap-2">
          <button
            onClick={() => noteContent && onCopy(noteContent)}
            className="p-1.5 rounded-sm hover:bg-slate-800 transition-colors text-slate-500 hover:text-white cursor-pointer"
            title="Copy Markdown"
          >
            {copied ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
          </button>
          <button
            onClick={onClose}
            className="p-1.5 rounded-sm hover:bg-red-500/20 hover:text-red-400 transition-colors text-slate-500 cursor-pointer"
            title="Close Note"
          >
            <X className="w-4 h-4" />
          </button>
        </div>
      </div>

      <div className="p-8 pb-32">
        {/* Action Result Overlay */}
        <AnimatePresence>
          {actionResult && (
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: 20 }}
              className="mb-8 p-6 bg-orange-500/5 border border-orange-500/20 rounded-sm relative group"
            >
              <div className="flex items-center justify-between mb-4">
                <h4 className="text-[10px] uppercase tracking-[0.2em] font-black text-orange-500">
                  {actionResult.type}
                </h4>
                <div className="flex items-center gap-3">
                  {actionResult.type === 'Actionable Tasks' && (
                    <button
                      onClick={() => onSaveTasks(actionResult.content)}
                      className="text-[9px] uppercase font-bold text-emerald-400 hover:text-emerald-300 transition-colors border border-emerald-500/30 px-2 py-0.5 rounded-sm bg-emerald-500/10 cursor-pointer"
                    >
                      Append to Note
                    </button>
                  )}
                  <button
                    onClick={onDismissActionResult}
                    className="text-slate-600 hover:text-white text-xs transition-colors italic cursor-pointer"
                  >
                    dismiss
                  </button>
                </div>
              </div>
              <div className="prose prose-invert prose-sm max-w-none text-slate-300 font-serif italic leading-relaxed">
                <ReactMarkdown>{actionResult.content}</ReactMarkdown>
              </div>
              <div className="absolute -bottom-px left-0 right-0 h-px bg-gradient-to-r from-transparent via-orange-500/50 to-transparent" />
            </motion.div>
          )}
        </AnimatePresence>

        {noteContent ? (
          <div className="flex flex-col gap-6">
            {(() => {
              let processedContent = noteContent;
              const frontmatter: Record<string, string> = {};

              if (processedContent.startsWith('---\n')) {
                const endIdx = processedContent.indexOf('\n---\n', 4);
                if (endIdx !== -1) {
                  const fmString = processedContent.substring(4, endIdx);
                  fmString.split('\n').forEach((line) => {
                    const colonIdx = line.indexOf(':');
                    if (colonIdx !== -1) {
                      frontmatter[line.substring(0, colonIdx).trim()] = line
                        .substring(colonIdx + 1)
                        .trim();
                    }
                  });
                  processedContent = processedContent.substring(endIdx + 5);
                }
              }

              processedContent = processedContent.replace(/\[\[(.*?)\]\]/g, '**`$1`**');

              return (
                <>
                  {Object.keys(frontmatter).length > 0 && (
                    <div className="flex flex-wrap gap-2 p-4 bg-[#111] border border-slate-800 rounded-sm">
                      {Object.entries(frontmatter).map(([k, v]) => (
                        <div
                          key={k}
                          className="flex items-center gap-2 bg-black px-2 py-1 rounded-sm border border-slate-800"
                        >
                          <span className="text-[10px] uppercase text-slate-500 font-bold tracking-wider">
                            {k}
                          </span>
                          <span className="text-xs text-slate-300 font-mono">{v}</span>
                        </div>
                      ))}
                    </div>
                  )}
                  <div className="prose prose-invert prose-slate max-w-none prose-headings:font-display prose-headings:font-light prose-headings:italic markdown-body">
                    <ReactMarkdown>{processedContent}</ReactMarkdown>
                  </div>
                </>
              );
            })()}
          </div>
        ) : (
          <div className="h-full flex items-center justify-center py-20">
            <Loader2 className="w-6 h-6 text-slate-700 animate-spin" />
          </div>
        )}
      </div>
    </motion.div>
  );
};
