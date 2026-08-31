import React from 'react';
import { motion, AnimatePresence } from 'motion/react';
import { OperationTask } from '../../types';

interface ActiveQueueOverlayProps {
  activeTasks: OperationTask[];
}

export const ActiveQueueOverlay: React.FC<ActiveQueueOverlayProps> = ({ activeTasks }) => {
  return (
    <AnimatePresence>
      {activeTasks.length > 0 && (
        <motion.div
          initial={{ opacity: 0, y: 100, scale: 0.95 }}
          animate={{ opacity: 1, y: 0, scale: 1 }}
          exit={{ opacity: 0, y: 100, scale: 0.95 }}
          className="fixed bottom-6 left-6 z-50 bg-[#0d0d0d] border border-orange-500/30 rounded-sm p-4 w-80 shadow-[0_10px_30px_rgba(249,115,22,0.15)] font-mono"
        >
          <div className="flex items-center justify-between mb-3 border-b border-slate-800 pb-2">
            <div className="flex items-center gap-2">
              <span className="relative flex h-2 w-2">
                <span className="animate-ping absolute inline-flex h-full w-full rounded-full bg-orange-400 opacity-75"></span>
                <span className="relative inline-flex rounded-full h-2 w-2 bg-orange-500"></span>
              </span>
              <span className="text-[10px] uppercase font-bold text-white">
                Active Queue ({activeTasks.length})
              </span>
            </div>
            <span className="text-[9px] text-slate-500">REALTIME</span>
          </div>

          <div className="space-y-3">
            {activeTasks.slice(0, 3).map((task) => (
              <div key={task.task_id || task.url} className="text-xs">
                <div className="flex justify-between text-[10px] text-slate-400 mb-1">
                  <span className="truncate max-w-[180px]">{task.url}</span>
                  <span className="text-orange-500">{task.progress || 0}%</span>
                </div>
                <div className="w-full bg-black h-1 rounded-full overflow-hidden border border-slate-900">
                  <div
                    className="bg-orange-500 h-full transition-all duration-500"
                    style={{ width: `${task.progress || 0}%` }}
                  />
                </div>
                <div className="text-[9px] text-slate-500 italic mt-1 truncate">
                  {task.status}...
                </div>
              </div>
            ))}
          </div>
        </motion.div>
      )}
    </AnimatePresence>
  );
};
