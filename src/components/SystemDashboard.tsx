import React, { useState, useEffect } from 'react';
import { 
  Activity, 
  AlertCircle, 
  Clock, 
  ExternalLink, 
  Trash2, 
  CheckCircle, 
  Loader2, 
  Search,
  Database,
  Zap,
  BarChart3,
  TrendingUp,
  Youtube,
  Instagram,
  Video,
  FileText
} from 'lucide-react';

interface Task {
  task_id?: string;
  url: string;
  status: string;
  state?: string;
  progress?: number;
  start_time: string;
  finished_at?: string | null;
  error?: string | null;
}

interface LogEntry {
  timestamp: string;
  url: string;
  error: string;
  detail?: string;
}

interface Note {
  title: string;
  fileName: string;
  date: string;
  url?: string;
  platform?: string;
  type?: string;
  transcript_status?: string;
  ai_model?: string;
}

const SystemDashboard: React.FC = () => {
  const [tasks, setTasks] = useState<Task[]>([]);
  const [recentTasks, setRecentTasks] = useState<Task[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [notes, setNotes] = useState<Note[]>([]);
  const [config, setConfig] = useState<any>(null);
  const [isLoading, setIsLoading] = useState(true);
  const [searchTerm, setSearchTerm] = useState('');

  const fetchStatus = async () => {
    try {
      const res = await fetch('/api/status');
      const data = await res.json();
      setTasks(data.active_tasks || []);
      setRecentTasks(data.recent_tasks || []);
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
    }
  };

  const fetchNotesData = async () => {
    try {
      const res = await fetch('/api/notes');
      const data = await res.json();
      setNotes(data || []);
    } catch (err) {
      console.error('Failed to fetch notes:', err);
    }
  };

  const fetchConfig = async () => {
    try {
      const res = await fetch('/api/config');
      const data = await res.json();
      setConfig(data);
    } catch (err) {
      console.error('Failed to fetch config:', err);
    } finally {
      setIsLoading(false);
    }
  };

  useEffect(() => {
    fetchStatus();
    fetchLogs();
    fetchNotesData();
    fetchConfig();
    const interval = setInterval(fetchStatus, 2000);
    const logsInterval = setInterval(fetchLogs, 10000);
    const notesInterval = setInterval(fetchNotesData, 30000);
    return () => {
      clearInterval(interval);
      clearInterval(logsInterval);
      clearInterval(notesInterval);
    };
  }, []);

  const clearLogs = async () => {
    if (!confirm('Clear all error logs?')) return;
    try {
      await fetch('/api/logs/clear', { method: 'POST' });
      setLogs([]);
    } catch (err) {
      console.error('Failed to clear logs:', err);
    }
  };

  // --- Analytics Calculations ---
  const platformStats = notes.reduce((acc: any, note) => {
    const p = note.platform || 'other';
    acc[p] = (acc[p] || 0) + 1;
    return acc;
  }, {});

  const typeStats = notes.reduce((acc: any, note) => {
    const t = note.type || 'other';
    acc[t] = (acc[t] || 0) + 1;
    return acc;
  }, {});

  const transcriptSuccess = notes.filter(n => n.transcript_status === 'complete').length;
  const transcriptRate = notes.length ? Math.round((transcriptSuccess / notes.length) * 100) : 0;
  
  const successCount = recentTasks.filter(t => t.state === 'completed').length + notes.length;
  const totalAttempts = successCount + logs.length;
  const healthScore = totalAttempts ? Math.round((successCount / totalAttempts) * 100) : 100;

  const filteredLogs = logs.filter(log => 
    log.url.toLowerCase().includes(searchTerm.toLowerCase()) ||
    log.error.toLowerCase().includes(searchTerm.toLowerCase())
  );

  return (
    <div className="space-y-8 p-6 bg-[#050505] min-h-full">
      {/* Header */}
      <div className="flex items-center justify-between border-b border-white/5 pb-6">
        <div className="flex items-center gap-4">
          <div className="p-3 bg-indigo-500/10 rounded-sm border border-indigo-500/20 shadow-[0_0_15px_rgba(99,102,241,0.1)]">
            <Activity className="w-6 h-6 text-indigo-400" />
          </div>
          <div>
            <h2 className="text-2xl font-display font-light italic tracking-tight text-white uppercase">System Mission Control</h2>
            <p className="text-[10px] font-mono text-zinc-500 uppercase tracking-[0.2em] mt-1">Real-time Node Status & Intelligence Analytics</p>
          </div>
        </div>
        <div className="flex items-center gap-3">
          <div className="px-4 py-2 bg-black border border-zinc-800 rounded-sm flex flex-col items-end">
            <span className="text-[10px] text-zinc-500 uppercase font-bold">Health Score</span>
            <span className={cn("text-lg font-mono font-bold", healthScore > 80 ? "text-emerald-500" : "text-orange-500")}>{healthScore}%</span>
          </div>
          <button 
            onClick={clearLogs}
            className="flex items-center gap-2 px-4 py-2 text-xs font-bold text-red-400 hover:bg-red-500/10 rounded-sm transition-all border border-red-500/20 uppercase tracking-widest"
          >
            <Trash2 className="w-3.5 h-3.5" />
            Wipe Logs
          </button>
        </div>
      </div>

      {/* Analytics Grid */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
        {[
          { label: 'Total Knowledge', value: notes.length, icon: <Database className="w-4 h-4 text-indigo-400" />, sub: 'Indexed Nodes' },
          { label: 'Transcripts', value: `${transcriptRate}%`, icon: <Zap className="w-4 h-4 text-orange-400" />, sub: 'Success Rate' },
          { label: 'Active Ops', value: tasks.length, icon: <Loader2 className={cn("w-4 h-4 text-indigo-400", tasks.length > 0 && "animate-spin")} />, sub: 'Running Tasks' },
          { label: 'System Errors', value: logs.length, icon: <AlertCircle className="w-4 h-4 text-red-400" />, sub: 'Total Criticals' },
        ].map((stat, i) => (
          <div key={i} className="bg-[#0a0a0a] border border-white/5 p-4 rounded-sm hover:border-white/10 transition-colors">
            <div className="flex items-center justify-between mb-2">
              <span className="text-[10px] uppercase font-bold text-zinc-500 tracking-widest">{stat.label}</span>
              {stat.icon}
            </div>
            <div className="text-2xl font-mono font-bold text-white mb-1">{stat.value}</div>
            <div className="text-[10px] font-mono text-zinc-600 uppercase">{stat.sub}</div>
          </div>
        ))}
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Visual Analytics */}
        <div className="lg:col-span-2 space-y-6">
          <div className="bg-[#0a0a0a] border border-white/5 rounded-sm p-6">
            <div className="flex items-center justify-between mb-6">
              <div className="flex items-center gap-2 text-xs font-bold text-zinc-400 uppercase tracking-widest">
                <BarChart3 className="w-4 h-4" />
                Intelligence Distribution
              </div>
              <div className="flex gap-4">
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-indigo-500" />
                  <span className="text-[10px] text-zinc-500 uppercase font-mono">Platform</span>
                </div>
                <div className="flex items-center gap-2">
                  <div className="w-2 h-2 rounded-full bg-orange-500" />
                  <span className="text-[10px] text-zinc-500 uppercase font-mono">Type</span>
                </div>
              </div>
            </div>

            <div className="space-y-8">
              {/* Platform Bars */}
              <div>
                <div className="text-[10px] text-zinc-500 uppercase font-bold mb-4 tracking-widest flex items-center gap-2">
                  <TrendingUp className="w-3 h-3" /> Source Platforms
                </div>
                <div className="space-y-4">
                  {Object.entries(platformStats).sort((a, b) => (b[1] as number) - (a[1] as number)).map(([p, count]: any) => {
                    const pct = Math.round((count / notes.length) * 100);
                    return (
                      <div key={p} className="space-y-1.5">
                        <div className="flex justify-between text-[10px] font-mono uppercase">
                          <span className="text-zinc-300 flex items-center gap-2">
                            {p === 'youtube' ? <Youtube className="w-3 h-3 text-red-500" /> : p === 'instagram' ? <Instagram className="w-3 h-3 text-pink-500" /> : <Database className="w-3 h-3" />}
                            {p}
                          </span>
                          <span className="text-zinc-500">{count} nodes ({pct}%)</span>
                        </div>
                        <div className="h-1 bg-white/5 rounded-full overflow-hidden">
                          <div 
                            className="h-full bg-indigo-500 shadow-[0_0_10px_rgba(99,102,241,0.5)] transition-all duration-1000" 
                            style={{ width: `${pct}%` }} 
                          />
                        </div>
                      </div>
                    );
                  })}
                </div>
              </div>

              {/* Media Type Icons */}
              <div className="grid grid-cols-2 sm:grid-cols-4 gap-4">
                {Object.entries(typeStats).map(([t, count]: any) => (
                  <div key={t} className="bg-black border border-white/5 p-3 rounded-sm text-center">
                    <div className="flex justify-center mb-2">
                      {t.includes('video') ? <Video className="w-4 h-4 text-orange-500" /> : <FileText className="w-4 h-4 text-zinc-400" />}
                    </div>
                    <div className="text-lg font-mono font-bold text-white">{count}</div>
                    <div className="text-[10px] font-mono text-zinc-600 uppercase truncate">{t.replace('-', ' ')}</div>
                  </div>
                ))}
              </div>
            </div>
          </div>

          {/* Active Operations */}
          <div className="bg-[#0a0a0a] border border-white/5 rounded-sm overflow-hidden">
            <div className="p-4 border-b border-white/5 flex items-center gap-2 text-xs font-bold text-zinc-400 uppercase tracking-widest">
              <Clock className="w-4 h-4 text-indigo-400" />
              Live Process Stream ({tasks.length})
            </div>
            <div className="min-h-[200px]">
              {tasks.length === 0 ? (
                <div className="flex flex-col items-center justify-center py-12 text-zinc-600">
                  <div className="w-10 h-10 border border-zinc-800 rounded-full flex items-center justify-center mb-3 opacity-20">
                    <CheckCircle className="w-6 h-6" />
                  </div>
                  <p className="text-xs uppercase font-mono tracking-widest italic">All systems nominal. No active tasks.</p>
                </div>
              ) : (
                <div className="divide-y divide-white/5">
                  {tasks.map((task, idx) => (
                    <div key={idx} className="p-4 flex items-center justify-between hover:bg-white/[0.02] transition-colors group">
                      <div className="flex flex-col gap-1 min-w-0 max-w-[60%]">
                        <span className="text-xs font-medium text-indigo-300 truncate font-mono">{task.url}</span>
                        <span className="text-[10px] text-zinc-600 uppercase font-mono">ID: {task.task_id || 'LOCAL'} • {new Date(task.start_time).toLocaleTimeString()}</span>
                      </div>
                      <div className="flex items-center gap-4">
                        {typeof task.progress === 'number' && (
                          <div className="flex flex-col items-end gap-1">
                            <span className="text-[10px] font-mono text-zinc-500">{task.progress}%</span>
                            <div className="w-20 h-1 bg-white/5 rounded-full overflow-hidden">
                              <div className="h-full bg-indigo-500 animate-pulse" style={{ width: `${task.progress}%` }} />
                            </div>
                          </div>
                        )}
                        <div className="px-3 py-1 bg-indigo-500/10 border border-indigo-500/20 rounded-sm flex items-center gap-2">
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
        </div>

        {/* Sidebar Analytics */}
        <div className="space-y-6">
          {/* Recent History */}
          <div className="bg-[#0a0a0a] border border-white/5 rounded-sm overflow-hidden flex flex-col h-full">
            <div className="p-4 border-b border-white/5 text-[10px] font-bold text-zinc-400 uppercase tracking-[0.2em]">Recent Node Syncs</div>
            <div className="flex-1 overflow-y-auto max-h-[300px]">
              {recentTasks.length > 0 ? (
                <div className="divide-y divide-white/5">
                  {recentTasks.slice(0, 8).map((task, idx) => (
                    <div key={task.task_id || idx} className="p-3 hover:bg-white/[0.01] transition-colors">
                      <div className="text-[10px] text-zinc-300 truncate font-mono mb-1">{task.url}</div>
                      <div className="flex justify-between items-center">
                        <span className="text-[9px] text-zinc-600 font-mono uppercase">{task.status}</span>
                        <span className={cn(
                          "text-[9px] font-black uppercase tracking-tighter",
                          task.state === 'failed' ? "text-red-500" : "text-emerald-500"
                        )}>
                          {task.state || 'OK'}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              ) : (
                <div className="p-8 text-center text-[10px] text-zinc-700 font-mono italic">No history available.</div>
              )}
            </div>
          </div>

          {/* Error Feed */}
          <div className="bg-[#0a0a0a] border border-red-500/10 rounded-sm overflow-hidden flex flex-col">
            <div className="p-4 border-b border-white/5 flex items-center justify-between">
              <div className="text-[10px] font-bold text-red-400 uppercase tracking-[0.2em] flex items-center gap-2">
                <AlertCircle className="w-3 h-3" /> System Faults
              </div>
              <div className="relative">
                <Search className="absolute left-2 top-1/2 -translate-y-1/2 w-3 h-3 text-zinc-600" />
                <input 
                  type="text" 
                  placeholder="Filter..."
                  value={searchTerm}
                  onChange={(e) => setSearchTerm(e.target.value)}
                  className="pl-6 pr-2 py-1 text-[9px] bg-black border border-white/5 rounded-sm focus:outline-none focus:border-red-500/30 transition-colors text-zinc-400 w-24 font-mono uppercase"
                />
              </div>
            </div>
            <div className="max-h-[350px] overflow-y-auto divide-y divide-white/5">
              {filteredLogs.length === 0 ? (
                <div className="p-12 text-center text-zinc-700 text-[10px] font-mono uppercase italic">
                  {searchTerm ? 'Zero matches.' : 'Vault Integrity Nominal.'}
                </div>
              ) : (
                filteredLogs.map((log, idx) => (
                  <div key={idx} className="p-3 space-y-2 group">
                    <div className="flex items-start justify-between">
                      <div className="min-w-0">
                        <div className="flex items-center gap-2 mb-1">
                          <span className="text-[9px] font-black text-red-500 uppercase tracking-widest">FAULT</span>
                          <span className="text-[8px] text-zinc-600 font-mono">{new Date(log.timestamp).toLocaleTimeString()}</span>
                        </div>
                        <p className="text-[10px] font-medium text-zinc-400 truncate pr-2">{log.error}</p>
                      </div>
                      <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                        <button 
                          onClick={() => {
                            navigator.clipboard.writeText(log.url);
                            alert('URL ready for re-ingestion.');
                          }}
                          className="p-1 hover:bg-zinc-800 rounded transition-colors text-zinc-600 hover:text-indigo-400"
                        >
                          <Zap className="w-3 h-3" />
                        </button>
                        <a href={log.url} target="_blank" rel="noreferrer" className="p-1 hover:bg-zinc-800 rounded transition-colors text-zinc-600 hover:text-white">
                          <ExternalLink className="w-3 h-3" />
                        </a>
                      </div>
                    </div>
                  </div>
                ))
              )}
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};

// Helper for class merging
function cn(...classes: any[]) {
  return classes.filter(Boolean).join(' ');
}

export default SystemDashboard;
