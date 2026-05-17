import React, { useEffect, useState } from 'react';
import { MessageSquare, Clock, Plus } from 'lucide-react';
import { format } from 'date-fns';
import { cn } from '../lib/utils';

interface ChatSession {
  session_id: string;
  title: string;
  last_updated: string;
  message_count: number;
}

interface ChatSidebarProps {
  onSelectSession: (sessionId: string) => void;
  currentSessionId: string | null;
  onNewSession: () => void;
}

export default function ChatSidebar({ onSelectSession, currentSessionId, onNewSession }: ChatSidebarProps) {
  const [sessions, setSessions] = useState<ChatSession[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchChats();
  }, [currentSessionId]);

  const fetchChats = async () => {
    try {
      const res = await fetch('/api/chats');
      const data = await res.json();
      setSessions(data.sessions || []);
    } catch (e) {
      console.error('Failed to fetch chat sessions', e);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="w-64 border-l border-slate-800 bg-[#111] flex flex-col h-full">
      <div className="p-4 border-b border-slate-800 flex items-center justify-between">
        <h2 className="text-xs uppercase text-slate-500 tracking-widest font-bold flex items-center gap-2">
          <Clock className="w-4 h-4" /> History
        </h2>
        <button
          onClick={onNewSession}
          className="p-1 hover:bg-slate-800 rounded transition-colors text-slate-500 hover:text-white"
          title="New Chat"
        >
          <Plus className="w-4 h-4" />
        </button>
      </div>
      <div className="flex-1 overflow-y-auto p-2 space-y-1">
        {loading ? (
          <div className="text-center text-xs text-slate-500 py-4">Loading...</div>
        ) : sessions.length === 0 ? (
          <div className="text-center text-xs text-slate-500 py-4">No history yet</div>
        ) : (
          sessions.map(session => (
            <button
              key={session.session_id}
              onClick={() => onSelectSession(session.session_id)}
              className={cn(
                "w-full text-left p-3 rounded-sm text-xs font-mono transition-all group flex items-start gap-3",
                currentSessionId === session.session_id
                  ? "bg-slate-800 text-white border-l-2 border-orange-500"
                  : "text-slate-400 hover:bg-slate-900/50 hover:text-slate-200 border-l-2 border-transparent"
              )}
            >
              <MessageSquare className="w-4 h-4 shrink-0 mt-0.5 opacity-50 group-hover:opacity-100 group-hover:text-orange-500 transition-colors" />
              <div className="overflow-hidden">
                <div className="truncate font-medium">{session.title}</div>
                <div className="text-[10px] text-slate-600 mt-1 flex items-center gap-2">
                  <span>{format(new Date(session.last_updated), 'MMM d, h:mm a')}</span>
                  <span>•</span>
                  <span>{session.message_count} msgs</span>
                </div>
              </div>
            </button>
          ))
        )}
      </div>
    </div>
  );
}
