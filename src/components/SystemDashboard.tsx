import React, { useState, useEffect } from 'react';
import { Activity, AlertCircle, Clock, ExternalLink, Trash2, CheckCircle, Loader2, Search } from 'lucide-react';

interface Task {
  url: string;
  status: string;
  start_time: string;
}

interface LogEntry {
  timestamp: string;
  url: string;
  error: string;
  detail?: string;
}

const SystemDashboard: React.FC = () => {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [isLoading, setIsLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  const fetchStatus = async () => {
    try {
      const res = await fetch('/api/status');
      const data = await res.json();
      setTasks(data.active_tasks || []);
    } catch (err) {
      console.error('Failed to fetch status:', err);
    }
  };

  const fetchLogs = async () => {
    try {
      const res = await fetch('/api/logs');
      const data = await res.json();
      setLogs(data || []);
    } catch (err) {
      console.error('Failed to fetch logs:', err);
    } finally {
      setIsLoading(false);
    }
  };

  const filteredLogs = logs.filter(log => 
    log.url.toLowerCase().includes(searchTerm.toLowerCase()) ||
    log.error.toLowerCase().includes(searchTerm.toLowerCase())
  );

  const clearLogs = async () => {
    if (!confirm('Clear all error logs?')) return;
    try {
      await fetch('/api/logs/clear', { method: 'POST' });
      setLogs([]);
    } catch (err) {
      console.error('Failed to clear logs:', err);
    }
  };

  useEffect(() => {
    fetchStatus();
    fetchLogs();
    const interval = setInterval(fetchStatus, 2000); // Poll tasks frequently
    const logsInterval = setInterval(fetchLogs, 10000); // Poll logs less often
    return () => {
      clearInterval(interval);
      clearInterval(logsInterval);
    };
  }, []);

  return (
    <div className="space-y-8 p-6 bg-[#0a0a0a] rounded-xl border border-[#222] text-white">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div className="p-2 bg-indigo-500/10 rounded-lg">
            <Activity className="w-6 h-6 text-indigo-400" />
          </div>
          <h2 className="text-xl font-bold tracking-tight">System Mission Control</h2>
        </div>
        <button 
          onClick={clearLogs}
          className="flex items-center gap-2 px-3 py-1.5 text-xs font-medium text-red-400 hover:bg-red-500/10 rounded-md transition-colors border border-red-500/20"
        >
          <Trash2 className="w-3.5 h-3.5" />
          CLEAR ERROR LOGS
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
        {/* Active Tasks */}
        <div className="space-y-4">
          <div className="flex items-center gap-2 text-sm font-semibold text-zinc-400 uppercase tracking-wider">
            <Clock className="w-4 h-4" />
            Active Operations ({tasks.length})
          </div>
          
          <div className="min-h-[200px] bg-[#111] rounded-lg border border-[#222] overflow-hidden">
            {tasks.length === 0 ? (
              <div className="flex flex-col items-center justify-center h-full text-zinc-600 py-12">
                <CheckCircle className="w-8 h-8 mb-2 opacity-20" />
                <p className="text-sm">No active tasks. System idle.</p>
              </div>
            ) : (
              <div className="divide-y divide-[#222]">
                {tasks.map((task, idx) => (
                  <div key={idx} className="p-4 flex items-center justify-between hover:bg-[#151515] transition-colors">
                    <div className="flex flex-col gap-1 max-w-[70%]">
                      <span className="text-sm font-medium text-indigo-300 truncate">{task.url}</span>
                      <span className="text-xs text-zinc-500">Started: {new Date(task.start_time).toLocaleTimeString()}</span>
                    </div>
                    <div className="flex items-center gap-3">
                      <div className="px-2.5 py-1 bg-indigo-500/10 border border-indigo-500/20 rounded-full flex items-center gap-2">
                        <Loader2 className="w-3 h-3 text-indigo-400 animate-spin" />
                        <span className="text-[10px] font-bold text-indigo-400 uppercase tracking-widest">{task.status}</span>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Error Logs */}
        <div className="space-y-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-2 text-sm font-semibold text-zinc-400 uppercase tracking-wider">
              <AlertCircle className="w-4 h-4" />
              Recent Error Logs ({filteredLogs.length})
            </div>
            <div className="relative">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-zinc-500" />
              <input 
                type="text" 
                placeholder="Search logs..."
                value={searchTerm}
                onChange={(e) => setSearchTerm(e.target.value)}
                className="pl-8 pr-3 py-1 text-xs bg-black border border-[#222] rounded-md focus:outline-none focus:border-indigo-500/50 transition-colors text-zinc-300 w-48"
              />
            </div>
          </div>

          <div className="max-h-[400px] overflow-y-auto bg-[#111] rounded-lg border border-[#222] divide-y divide-[#222]">
            {filteredLogs.length === 0 ? (
              <div className="p-12 text-center text-zinc-600 text-sm">
                {searchTerm ? 'No logs match your search.' : 'No errors recorded. All systems green.'}
              </div>
            ) : (
              filteredLogs.map((log, idx) => (
                <div key={idx} className="p-4 space-y-2 group">
                  <div className="flex items-start justify-between">
                    <div className="flex flex-col gap-1">
                      <div className="flex items-center gap-2">
                        <span className="text-xs font-bold text-red-500 uppercase tracking-widest">CRITICAL ERROR</span>
                        <span className="text-[10px] text-zinc-500">{new Date(log.timestamp).toLocaleString()}</span>
                      </div>
                      <p className="text-sm font-medium text-zinc-200 line-clamp-1">{log.error}</p>
                    </div>
                    <div className="flex items-center gap-2">
                      <button 
                        onClick={() => {
                          navigator.clipboard.writeText(log.url);
                          alert('URL copied to clipboard! Paste it into the INGEST bar to retry.');
                        }}
                        className="p-1.5 hover:bg-zinc-800 rounded-md transition-colors text-zinc-500 hover:text-indigo-400 text-[10px] font-bold"
                        title="Copy URL to Retry"
                      >
                        RETRY
                      </button>
                      <a href={log.url} target="_blank" rel="noreferrer" className="p-1.5 hover:bg-zinc-800 rounded-md transition-colors text-zinc-500 hover:text-white">
                        <ExternalLink className="w-4 h-4" />
                      </a>
                    </div>
                  </div>
                  <div className="text-[10px] font-mono text-zinc-500 bg-black/30 p-2 rounded border border-[#222] break-all max-h-[60px] overflow-hidden group-hover:max-h-none transition-all duration-300">
                    URL: {log.url}
                    {log.detail && (
                      <div className="mt-1 opacity-0 group-hover:opacity-100 transition-opacity whitespace-pre-wrap">
                        {log.detail.split('\n').slice(0, 5).join('\n')}...
                      </div>
                    )}
                  </div>
                </div>
              ))
            )}
          </div>
        </div>
      </div>
    </div>
  );
};

export default SystemDashboard;
