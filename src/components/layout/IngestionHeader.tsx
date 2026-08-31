import React from 'react';
import {
  Zap,
  Loader2,
  Plus,
  Mic,
  MicOff,
  Shield,
  CheckCircle2,
  Moon,
  Sun,
  Activity,
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import { OperationTask, Theme } from '../../types';
import { cn } from '../../lib/utils';

interface IngestionHeaderProps {
  url: string;
  loadingNote: boolean;
  ingestStatus: string | null;
  error: string | null;
  success: string | null;
  isDragging: boolean;
  isRecording: boolean;
  fileInputRef: React.RefObject<HTMLInputElement | null>;
  visibleTask?: OperationTask;
  visibleTaskProgress: string | null;
  theme: Theme;
  showDashboard: boolean;
  activeModel: string;
  onUrlChange: (url: string) => void;
  onIngest: (e: React.FormEvent) => void;
  onFileUpload: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onDragOver: (e: React.DragEvent) => void;
  onDragLeave: () => void;
  onDrop: (e: React.DragEvent) => void;
  onToggleRecording: () => void;
  onToggleTheme: () => void;
  onToggleDashboard: () => void;
}

export const IngestionHeader: React.FC<IngestionHeaderProps> = ({
  url,
  loadingNote,
  ingestStatus,
  error,
  success,
  isDragging,
  isRecording,
  fileInputRef,
  visibleTask,
  visibleTaskProgress,
  theme,
  showDashboard,
  activeModel,
  onUrlChange,
  onIngest,
  onFileUpload,
  onDragOver,
  onDragLeave,
  onDrop,
  onToggleRecording,
  onToggleTheme,
  onToggleDashboard,
}) => {
  return (
    <header className="h-16 border-b border-slate-800 bg-black/60 backdrop-blur-md flex items-center px-8 justify-between z-10">
      <div className="flex-1 max-w-2xl flex flex-col relative">
        <form
          onSubmit={onIngest}
          onDragOver={onDragOver}
          onDragLeave={onDragLeave}
          onDrop={onDrop}
          className={cn(
            'flex items-center gap-2 group transition-all duration-200 border rounded-sm p-1',
            isDragging
              ? 'border-orange-500 bg-orange-500/5 ring-1 ring-orange-500/30'
              : 'border-transparent bg-transparent'
          )}
        >
          <div className="relative flex-1 flex items-center group">
            <Zap className="absolute left-4 w-4 h-4 text-orange-500 opacity-50 group-focus-within:opacity-100 transition-opacity" />
            <input
              type="text"
              placeholder={
                isDragging
                  ? 'Drop file here to ingest...'
                  : 'Paste URL (YouTube, TikTok, Instagram, Web) or drop file...'
              }
              className="w-full bg-black border border-slate-800 rounded-sm py-2 pl-12 pr-4 text-sm focus:outline-none focus:ring-1 focus:ring-orange-500/50 transition-all font-mono placeholder-slate-700 text-slate-300"
              value={url}
              onChange={(e) => onUrlChange(e.target.value)}
              disabled={loadingNote}
            />
            {loadingNote && (
              <div className="absolute right-4 flex items-center gap-3">
                <div className="text-[10px] text-orange-500/70 font-mono animate-pulse">
                  {ingestStatus}
                </div>
                <Loader2 className="w-4 h-4 text-orange-500 animate-spin" />
              </div>
            )}
            {!loadingNote && url && (
              <button
                type="submit"
                className="absolute right-2 px-3 py-1 rounded-sm bg-orange-500 text-black text-[10px] font-bold uppercase tracking-wider hover:bg-orange-400 transition-colors cursor-pointer"
              >
                Ingest
              </button>
            )}
          </div>

          <input
            type="file"
            accept=".pdf,.txt,.md,.mp3,.wav,.m4a,.ogg,.aac,.png,.jpg,.jpeg,.webp"
            className="hidden"
            ref={fileInputRef}
            onChange={onFileUpload}
          />
          <button
            type="button"
            onClick={() => fileInputRef.current?.click()}
            disabled={loadingNote}
            className="px-4 py-2 bg-slate-800 border border-slate-700 rounded-sm hover:bg-slate-700 transition-colors text-slate-300 font-mono text-xs disabled:opacity-50 flex items-center gap-2 cursor-pointer"
            title="Upload Document, Audio, or Image"
          >
            <Plus className="w-4 h-4" /> Upload
          </button>

          <button
            type="button"
            onClick={onToggleRecording}
            disabled={loadingNote}
            className={cn(
              'px-4 py-2 border rounded-sm transition-all font-mono text-xs flex items-center gap-2 cursor-pointer',
              isRecording
                ? 'bg-red-500/20 border-red-500 text-red-500 animate-pulse font-bold'
                : 'bg-slate-800 border-slate-700 hover:bg-slate-700 text-slate-300'
            )}
            title={isRecording ? 'Stop Recording' : 'Record Voice Note'}
          >
            {isRecording ? (
              <MicOff className="w-4 h-4" />
            ) : (
              <Mic className="w-4 h-4 text-orange-500" />
            )}
            {isRecording ? 'REC...' : 'REC'}
          </button>
        </form>

        <AnimatePresence>
          {(error || success) && (
            <motion.div
              initial={{ opacity: 0, y: -10 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -10 }}
              className={cn(
                'absolute top-full left-0 right-0 mt-2 p-2 rounded-sm text-[10px] uppercase tracking-wider font-bold flex items-center gap-2 border z-30',
                error
                  ? 'bg-red-500/10 border-red-500/20 text-red-500'
                  : 'bg-emerald-500/10 border-emerald-500/20 text-emerald-500'
              )}
            >
              {error ? <Shield className="w-3 h-3" /> : <CheckCircle2 className="w-3 h-3" />}
              {error || success}
            </motion.div>
          )}
        </AnimatePresence>
      </div>

      <div className="flex items-center gap-4 ml-8">
        {visibleTask && (
          <div
            className={cn(
              'hidden xl:flex items-center gap-2 max-w-xs border rounded-sm px-3 py-2 bg-black font-mono',
              visibleTask.state === 'failed'
                ? 'border-red-500/30 text-red-400'
                : 'border-orange-500/30 text-orange-400'
            )}
          >
            {visibleTask.state === 'failed' ? (
              <Shield className="w-4 h-4 shrink-0" />
            ) : (
              <Loader2 className="w-4 h-4 shrink-0 animate-spin" />
            )}
            <div className="min-w-0">
              <div className="text-[10px] uppercase tracking-widest truncate">
                {visibleTask.state === 'failed' ? 'Last ingest failed' : 'Active ingest'}
                {visibleTaskProgress ? ` - ${visibleTaskProgress}` : ''}
              </div>
              <div className="text-[10px] text-slate-400 truncate">{visibleTask.status}</div>
            </div>
          </div>
        )}
        <div className="h-4 w-px bg-slate-800" />
        <div className="flex items-center gap-4">
          <button
            onClick={onToggleTheme}
            className="flex items-center justify-center p-2 rounded-sm border border-slate-800 hover:border-slate-600 bg-slate-900/50 text-slate-400 hover:text-white transition-all cursor-pointer"
            title={theme === 'light' ? 'Switch to Dark Mode' : 'Switch to Light Mode'}
          >
            {theme === 'light' ? (
              <Moon className="w-3.5 h-3.5" />
            ) : (
              <Sun className="w-3.5 h-3.5 text-orange-500 animate-pulse" />
            )}
          </button>

          <button
            onClick={onToggleDashboard}
            className={cn(
              'flex items-center gap-2 px-3 py-1.5 text-xs font-bold uppercase tracking-widest transition-all rounded-sm cursor-pointer',
              showDashboard
                ? 'bg-indigo-500/20 text-indigo-400 border border-indigo-500/50 shadow-[0_0_10px_rgba(99,102,241,0.2)]'
                : 'text-slate-500 hover:text-white border border-slate-800 hover:border-slate-600 bg-slate-900/50'
            )}
          >
            <Activity className="w-3.5 h-3.5" />
            {showDashboard ? 'Exit Status' : 'Mission Control'}
          </button>
          <div className="text-right">
            <p className="text-[10px] uppercase text-slate-500 tracking-widest leading-none mb-1">
              Active Model
            </p>
            <p className="text-xs font-mono text-white">{activeModel}</p>
          </div>
        </div>
      </div>
    </header>
  );
};
