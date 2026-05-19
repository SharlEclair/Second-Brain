import React from 'react';
import { format, subDays, isSameDay } from 'date-fns';

interface Note {
  title: string;
  fileName: string;
  date: string;
}

interface ActivityHeatmapProps {
  notes: Note[];
}

export default function ActivityHeatmap({ notes }: ActivityHeatmapProps) {
  // Generate last 90 days, ordered chronologically (oldest to newest)
  const days = Array.from({ length: 90 }, (_, i) => subDays(new Date(), 89 - i));

  // Count notes per day
  const getNoteCountForDay = (day: Date) => {
    return notes.filter(note => {
      try {
        const noteDate = new Date(note.date);
        return isSameDay(noteDate, day);
      } catch (e) {
        return false;
      }
    }).length;
  };

  // Get color scale class based on note count
  const getColorClass = (count: number) => {
    if (count === 0) return 'bg-[#111] border-slate-900';
    if (count === 1) return 'bg-orange-500/20 border-orange-500/30 text-orange-300';
    if (count === 2) return 'bg-orange-500/40 border-orange-500/50 text-orange-200';
    if (count === 3) return 'bg-orange-500/70 border-orange-500/80 text-orange-100';
    return 'bg-orange-500 border-orange-400 text-black'; // 4 or more
  };

  return (
    <div className="bg-black border border-slate-800 rounded-sm p-4">
      <div className="flex items-center justify-between mb-4 border-b border-slate-800 pb-2">
        <h3 className="text-xs uppercase tracking-widest font-bold text-slate-400">Ingestion Activity</h3>
        <span className="text-[9px] font-mono text-slate-600">Last 90 Days</span>
      </div>
      
      <div className="flex flex-col items-center">
        {/* Heatmap Grid */}
        <div className="grid grid-flow-col grid-rows-7 gap-1.5 p-1 select-none">
          {days.map((day, index) => {
            const count = getNoteCountForDay(day);
            const dateStr = format(day, 'MMM d, yyyy');
            return (
              <div
                key={index}
                className={`w-3.5 h-3.5 rounded-[2px] border transition-colors cursor-help relative group ${getColorClass(count)}`}
                title={`${count} note${count === 1 ? '' : 's'} on ${dateStr}`}
              >
                {/* Tooltip */}
                <div className="absolute bottom-full left-1/2 -translate-x-1/2 mb-1.5 hidden group-hover:block bg-black border border-slate-850 px-2 py-1 rounded-sm text-[8px] font-mono text-white whitespace-nowrap z-50 pointer-events-none shadow-xl">
                  {count} note{count === 1 ? '' : 's'} on {format(day, 'MMM d')}
                </div>
              </div>
            );
          })}
        </div>

        {/* Legend */}
        <div className="flex items-center justify-end w-full gap-1.5 mt-3 text-[8px] font-mono text-slate-600">
          <span>Less</span>
          <div className="w-2.5 h-2.5 rounded-[1px] bg-[#111] border border-slate-900"></div>
          <div className="w-2.5 h-2.5 rounded-[1px] bg-orange-500/20 border border-orange-500/30"></div>
          <div className="w-2.5 h-2.5 rounded-[1px] bg-orange-500/40 border border-orange-500/50"></div>
          <div className="w-2.5 h-2.5 rounded-[1px] bg-orange-500/70 border border-orange-500/80"></div>
          <div className="w-2.5 h-2.5 rounded-[1px] bg-orange-500 border border-orange-400"></div>
          <span>More</span>
        </div>
      </div>
    </div>
  );
}
