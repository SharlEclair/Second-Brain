import React from 'react';
import { ChevronDown, Brain, Send } from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import ReactMarkdown from 'react-markdown';
import { ChatMessage, Note } from '../../types';
import { cn } from '../../lib/utils';

interface ChatPanelProps {
  messages: ChatMessage[];
  chatInput: string;
  isTyping: boolean;
  isChatMinimized: boolean;
  useActiveNoteContext: boolean;
  selectedNote: Note | null;
  chatEndRef: React.RefObject<HTMLDivElement | null>;
  onChatInputChange: (value: string) => void;
  onChatSubmit: (e: React.FormEvent) => void;
  onToggleMinimize: (minimized: boolean) => void;
  onToggleActiveNoteContext: (useContext: boolean) => void;
  onPromoteToWiki: (msg: ChatMessage) => void;
}

export const ChatPanel: React.FC<ChatPanelProps> = ({
  messages,
  chatInput,
  isTyping,
  isChatMinimized,
  useActiveNoteContext,
  selectedNote,
  chatEndRef,
  onChatInputChange,
  onChatSubmit,
  onToggleMinimize,
  onToggleActiveNoteContext,
  onPromoteToWiki,
}) => {
  return (
    <AnimatePresence>
      {!isChatMinimized ? (
        <motion.section
          initial={{ x: 400 }}
          animate={{ x: 0 }}
          exit={{ x: 400 }}
          className="w-[400px] shadow-2xl relative bg-[#111] border-l border-slate-800 flex flex-col z-20 shrink-0"
        >
          {/* Header */}
          <div className="p-4 border-b border-slate-800 flex items-center justify-between bg-black/40 min-h-[57px]">
            <div className="flex items-center gap-3">
              <h2 className="text-xs uppercase text-slate-500 tracking-widest font-bold">
                Terminal / Chat
              </h2>
              <span className="text-[10px] font-mono bg-slate-800 px-2 py-1 text-slate-400 rounded-sm">
                RAG_ENABLED
              </span>
            </div>
            <button
              onClick={() => onToggleMinimize(true)}
              className="p-1 hover:bg-slate-800 rounded transition-colors text-slate-500 hover:text-white cursor-pointer"
              title="Minimize"
            >
              <ChevronDown className="w-4 h-4" />
            </button>
          </div>

          {/* Active Note Context Bar */}
          {selectedNote && (
            <div className="px-4 py-2 border-b border-slate-800 bg-[#0d0d0d] flex items-center justify-between">
              <div className="flex items-center gap-2 min-w-0">
                <Brain className="w-3.5 h-3.5 text-orange-500 shrink-0" />
                <span className="text-[10px] text-slate-400 font-mono uppercase truncate max-w-[220px]">
                  Active Context: {selectedNote.title}
                </span>
              </div>
              <label className="flex items-center gap-1.5 cursor-pointer select-none shrink-0">
                <input
                  type="checkbox"
                  checked={useActiveNoteContext}
                  onChange={(e) => onToggleActiveNoteContext(e.target.checked)}
                  className="rounded border-slate-800 bg-black text-orange-500 focus:ring-0 focus:ring-offset-0 w-3 h-3"
                />
                <span className="text-[9px] uppercase font-mono text-slate-500 font-bold hover:text-slate-400 transition-colors">
                  Focus Chat
                </span>
              </label>
            </div>
          )}

          {/* Message Stream */}
          <div className="flex-1 overflow-y-auto p-4 space-y-4 font-mono text-sm relative">
            {messages.length === 0 && (
              <div className="text-left text-slate-500">
                <p>{'>'} Ask questions about your ingested knowledge.</p>
                <p>{'>'} Cortex will synthesize answers from your vault.</p>
              </div>
            )}
            {messages.map((msg) => (
              <div
                key={msg.id}
                className={cn(
                  'flex flex-col gap-1.5',
                  msg.isAi
                    ? 'items-start border-l border-slate-700 pl-4 py-2 bg-slate-900/30'
                    : 'items-end'
                )}
              >
                <div
                  className={cn(
                    'text-xs leading-relaxed max-w-[95%]',
                    msg.isAi
                      ? 'text-slate-300 font-mono'
                      : 'bg-orange-500 text-black font-medium py-2 px-3 rounded-sm'
                  )}
                >
                  {msg.isAi ? <ReactMarkdown>{msg.text}</ReactMarkdown> : msg.text}
                </div>
                {msg.isAi && (
                  <button
                    onClick={() => onPromoteToWiki(msg)}
                    className="mt-2 text-[10px] uppercase font-bold tracking-widest text-orange-500/70 hover:text-orange-500 border border-orange-500/20 hover:border-orange-500/50 px-2 py-1 rounded-sm transition-all cursor-pointer"
                  >
                    Promote to Wiki Article
                  </button>
                )}
              </div>
            ))}
            {isTyping && (
              <div className="text-orange-500 animate-pulse font-mono text-sm pl-4">_</div>
            )}
            <div ref={chatEndRef} />
          </div>

          {/* Chat Form */}
          <div className="p-4 border-t border-slate-800 bg-[#111]">
            <form onSubmit={onChatSubmit} className="relative">
              <input
                type="text"
                value={chatInput}
                onChange={(e) => onChatInputChange(e.target.value)}
                placeholder="ASK YOUR BRAIN..."
                className="w-full bg-black border border-slate-800 rounded-sm py-3 pl-4 pr-12 text-sm text-white font-mono placeholder-slate-700 outline-none focus:border-orange-500/50 transition-colors"
              />
              <button
                type="submit"
                disabled={!chatInput.trim() || isTyping}
                className="absolute right-2 top-1/2 -translate-y-1/2 p-2 text-orange-500 hover:text-orange-400 disabled:text-slate-700 transition-colors cursor-pointer"
              >
                <Send className="w-4 h-4" />
              </button>
            </form>
          </div>
        </motion.section>
      ) : (
        <motion.button
          initial={{ scale: 0 }}
          animate={{ scale: 1 }}
          onClick={() => onToggleMinimize(false)}
          className="fixed bottom-8 right-8 w-14 h-14 bg-orange-500 text-black rounded-full flex items-center justify-center hover:bg-orange-400 transition-transform hover:scale-110 shadow-[0_0_15px_rgba(249,115,22,0.4)] z-50 cursor-pointer"
          title="Restore Terminal"
        >
          <Send className="w-5 h-5 -rotate-45" />
        </motion.button>
      )}
    </AnimatePresence>
  );
};
