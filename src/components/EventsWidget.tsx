import React, { useEffect, useState } from 'react';
import { Calendar, Clock, MapPin } from 'lucide-react';
import { format, parseISO } from 'date-fns';

interface Event {
  title: string;
  fileName: string;
  event_date: string;
  url: string;
  platform: string;
}

interface EventsWidgetProps {
  onSelectEvent: (note: any) => void;
}

export default function EventsWidget({ onSelectEvent }: EventsWidgetProps) {
  const [events, setEvents] = useState<Event[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchEvents();
  }, []);

  const fetchEvents = async () => {
    try {
      const res = await fetch('/api/events/upcoming');
      const data = await res.json();
      setEvents(data || []);
    } catch (e) {
      console.error('Failed to fetch events', e);
    } finally {
      setLoading(false);
    }
  };

  if (loading) return null;
  if (events.length === 0) return null;

  return (
    <div className="bg-black border border-slate-800 rounded-sm overflow-hidden mb-6">
      <div className="p-4 border-b border-slate-800 flex items-center gap-2 bg-orange-500/5">
        <Calendar className="w-4 h-4 text-orange-500" />
        <h3 className="text-xs uppercase tracking-widest font-bold text-slate-300">Upcoming Events</h3>
      </div>
      <div className="p-2 space-y-1">
        {events.map((event, i) => {
          const date = parseISO(event.event_date);
          return (
            <button
              key={i}
              onClick={() => onSelectEvent(event)}
              className="w-full text-left p-3 flex items-start gap-4 hover:bg-slate-900 transition-colors rounded-sm group"
            >
              <div className="flex flex-col items-center justify-center min-w-[50px] p-2 bg-slate-900 border border-slate-800 rounded-sm text-center">
                <span className="text-[10px] uppercase text-orange-500 font-bold">{format(date, 'MMM')}</span>
                <span className="text-lg font-display text-white">{format(date, 'd')}</span>
              </div>
              <div className="flex-1 overflow-hidden min-w-0">
                <h4 className="text-sm font-medium text-slate-200 truncate group-hover:text-orange-400 transition-colors">
                  {event.title}
                </h4>
                <div className="flex items-center gap-3 mt-1.5 text-[10px] text-slate-500 font-mono">
                  <span className="flex items-center gap-1"><Clock className="w-3 h-3" /> {format(date, 'h:mm a')}</span>
                  <span className="flex items-center gap-1 uppercase bg-slate-800 px-1.5 py-0.5 rounded-sm">{event.platform}</span>
                </div>
              </div>
            </button>
          );
        })}
      </div>
    </div>
  );
}
