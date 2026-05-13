import React, { useState, useEffect, useRef } from 'react';
import { 
  Brain, 
  Search, 
  Plus, 
  ExternalLink, 
  Clock, 
  ChevronRight, 
  Send, 
  RefreshCw,
  FileText,
  Settings,
  Shield,
  Zap,
  Loader2,
  CheckCircle2,
  Sparkles,
  Copy,
  Check,
  ChevronDown,
  Activity
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import ReactMarkdown from 'react-markdown';
import { format } from 'date-fns';
import { cn } from './lib/utils';
import SystemDashboard from './components/SystemDashboard';
import ChatSidebar from './components/ChatSidebar';

interface Note {
  title: string;
  fileName: string;
  date: string;
  source?: string;
}

interface ChatMessage {
  id: string;
  text: string;
  isAi: boolean;
  timestamp: Date;
}

interface OperationTask {
  task_id?: string;
  url: string;
  platform?: string;
  status: string;
  state?: string;
  progress?: number;
  start_time: string;
  updated_at?: string;
  finished_at?: string | null;
  error?: string | null;
}

export default function App() {
  const [url, setUrl] = useState('');
  const [loadingNote, setLoadingNote] = useState(false);
  const [notes, setNotes] = useState<Note[]>([]);
  const [selectedNote, setSelectedNote] = useState<Note | null>(null);
  const [noteContent, setNoteContent] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [chatInput, setChatInput] = useState('');
  const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
  const [isSyncing, setIsSyncing] = useState(false);
  const [isTyping, setIsTyping] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [ingestStatus, setIngestStatus] = useState<string | null>(null);
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [actionResult, setActionResult] = useState<{ type: string, content: string } | null>(null);

  const [copied, setCopied] = useState(false);
  const [showDashboard, setShowDashboard] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [activeModel, setActiveModel] = useState('GEMINI-2.5-FLASH-LITE');
  const [activeTasks, setActiveTasks] = useState<OperationTask[]>([]);
  const [recentTasks, setRecentTasks] = useState<OperationTask[]>([]);
  const [isChatMinimized, setIsChatMinimized] = useState(false);
  
  const chatEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetchNotes();
    fetchOperationStatus();
    fetch('/api/config').then(r => r.json()).then(d => {
      if (d.model) setActiveModel(d.model.replace('models/', '').toUpperCase());
    }).catch(() => {});

    const interval = setInterval(fetchOperationStatus, 2000);
    return () => clearInterval(interval);
  }, []);

  useEffect(() => {
    if (chatEndRef.current) {
      chatEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages]);

  useEffect(() => {
    const handleGlobalPaste = (e: ClipboardEvent) => {
      // Don't auto-ingest if user is actively typing in a form field
      const target = e.target as HTMLElement;
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return;

      const pastedText = e.clipboardData?.getData('text');
      if (pastedText && pastedText.startsWith('http')) {
        setUrl(pastedText);
        // We need a slight delay to ensure setUrl state is updated before triggering
        setTimeout(() => {
          const form = document.querySelector('form');
          if (form) form.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
        }, 50);
      }
    };

    window.addEventListener('paste', handleGlobalPaste);
    return () => window.removeEventListener('paste', handleGlobalPaste);
  }, []);

  const fetchNotes = async () => {
    try {
      const res = await fetch('/api/notes');
      const data = await res.json();
      setNotes(data);
    } catch (e) {
      console.error("Failed to fetch notes", e);
    }
  };

  const fetchOperationStatus = async () => {
    try {
      const res = await fetch('/api/status');
      const data = await res.json();
      setActiveTasks(data.active_tasks || []);
      setRecentTasks(data.recent_tasks || []);
    } catch (e) {
      console.error("Failed to fetch operation status", e);
    }
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setLoadingNote(true);
    setError(null);
    setSuccess(null);
    setIngestStatus(`Uploading ${file.name}...`);

    const formData = new FormData();
    formData.append('file', file);

    try {
      const response = await fetch('/api/upload', {
        method: 'POST',
        body: formData,
      });

      const data = await response.json();
      if (!response.ok) {
        throw new Error(data.detail || 'Upload failed');
      }

      setSuccess('PDF successfully ingested');
      fetchNotes();
      setUrl('');
      if (data.note) {
        handleSelectNote(data.note);
      }
    } catch (err: any) {
      setError(err.message || "Failed to process PDF.");
    } finally {
      setLoadingNote(false);
      setIngestStatus(null);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  };

  const handleIngest = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!url) return;
    
    setLoadingNote(true);
    setError(null);
    setSuccess(null);
    setIngestStatus('Initiating session...');

    try {
      const isQueue = url.includes("twitter.com") || url.includes("x.com");

      const headers: Record<string, string> = {
        'Content-Type': 'application/json',
      };

      if (isQueue) {
        headers['X-Queue'] = 'true';
      } else {
        headers['X-Stream'] = 'true';
      }

      const response = await fetch('/api/ingest', {
        method: 'POST',
        headers,
        body: JSON.stringify({ url })
      });

      if (isQueue) {
        const data = await response.json();
        setSuccess(data.message || 'Added to background queue');
        setUrl('');
        setLoadingNote(false);
        setIngestStatus(null);
        return;
      }

      if (!response.body) throw new Error('No response body');
      
      const reader = response.body.getReader();
      const decoder = new TextDecoder();
      let buffer = '';

      while (true) {
        const { value, done } = await reader.read();
        if (done) break;
        
        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop() || '';

        for (const line of lines) {
          if (!line.trim()) continue;
          const data = JSON.parse(line);
          
          if (data.status === 'status') {
            setIngestStatus(data.message);
          } else if (data.status === 'success' || data.status === 'existing') {
            await fetchNotes();
            await fetchOperationStatus();
            handleSelectNote(data.note);
            setUrl('');
            setSuccess(data.status === 'existing' ? 'Note already exists' : 'Note successfully ingested');
            setTimeout(() => setSuccess(null), 3000);
          } else if (data.status === 'error') {
            setError(data.message);
          }
        }
      }
    } catch (e: any) {
      console.error("Ingestion failed", e);
      setError("Network error or server is down");
    } finally {
      setLoadingNote(false);
      setIngestStatus(null);
      fetchOperationStatus();
    }
  };

  const handleAction = async (type: 'summarize' | 'deep_dive') => {
    if (!selectedNote) return;
    setActionLoading(type);
    setActionResult(null);
    
    try {
      const res = await fetch(`/api/notes/${selectedNote.fileName}/${type}`, { method: 'POST' });
      const data = await res.json();
      setActionResult({ 
        type: type === 'summarize' ? 'Quick Summary' : 'Deep Dive Analysis', 
        content: data.summary || data.deep_dive 
      });
    } catch (e) {
      setError("Action failed");
    } finally {
      setActionLoading(null);
    }
  };

  const handleCopy = (text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  };

  const handleSelectNote = async (note: Note) => {
    setSelectedNote(note);
    setNoteContent(null);
    try {
      const res = await fetch(`/api/notes/${note.fileName}`);
      const data = await res.text();
      setNoteContent(data);
    } catch (e) {
      console.error("Failed to fetch note content", e);
    }
  };

  const loadChatSession = async (sessionId: string) => {
    try {
      const res = await fetch(`/api/chats/${sessionId}`);
      const data = await res.json();
      if (data.messages) {
        const loadedMessages = [];
        data.messages.forEach((msg: any, index: number) => {
          loadedMessages.push({
            id: `user-${index}`,
            text: msg.query,
            isAi: false,
            timestamp: new Date(msg.timestamp)
          });
          loadedMessages.push({
            id: `ai-${index}`,
            text: msg.response,
            isAi: true,
            timestamp: new Date(msg.timestamp)
          });
        });
        setMessages(loadedMessages);
        setCurrentSessionId(sessionId);
      }
    } catch (e) {
      console.error("Failed to load chat session", e);
    }
  };

  const handleNewSession = () => {
    setCurrentSessionId(null);
    setMessages([]);
  };

  const handleChat = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!chatInput.trim()) return;

    const userMsg: ChatMessage = {
      id: Date.now().toString(),
      text: chatInput,
      isAi: false,
      timestamp: new Date()
    };
    
    setMessages(prev => [...prev, userMsg]);
    setChatInput('');
    setIsTyping(true);
    setError(null);

    try {
      const res = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: userMsg.text, session_id: currentSessionId })
      });
      const data = await res.json();
      
      if (data.response) {
        if (!currentSessionId && data.session_id) {
          setCurrentSessionId(data.session_id);
        }
        const aiMsg: ChatMessage = {
          id: (Date.now() + 1).toString(),
          text: data.response,
          isAi: true,
          timestamp: new Date()
        };
        setMessages(prev => [...prev, aiMsg]);
      } else {
        throw new Error(data.error || "Unknown AI error");
      }
    } catch (e: any) {
      console.error("Chat failed", e);
      setError(`Chat failed: ${e.message}`);
    } finally {
      setIsTyping(false);
    }
  };

  const handleSync = async () => {
    setIsSyncing(true);
    try {
      await fetch('/api/sync', { method: 'POST' });
      await new Promise(r => setTimeout(r, 2000)); // Simulate sync motion
      setIsSyncing(false);
    } catch (e) {
      console.error("Sync failed", e);
      setIsSyncing(false);
    }
  };

  const visibleTask = activeTasks[0] || recentTasks.find(task => task.state === 'failed');
  const visibleTaskProgress = typeof visibleTask?.progress === 'number' ? `${visibleTask.progress}%` : null;

  return (
    <div className="flex h-screen w-full bg-[#050505] font-sans text-slate-300 overflow-hidden p-0 sm:p-2">
      {/* Sidebar - Vault Explorer */}
      <aside className="w-80 flex flex-col border-r border-slate-800 bg-[#111]">
        <div className="p-6 border-b border-slate-800 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-sm bg-orange-500/10 flex items-center justify-center border border-orange-500/20">
              <Brain className="w-5 h-5 text-orange-500" />
            </div>
            <h1 className="font-display font-light italic text-xl tracking-tight text-white glow-text">BRAIN_VAULT</h1>
          </div>
          <button 
            onClick={handleSync}
            disabled={isSyncing}
            className="flex items-center gap-2 px-3 py-1.5 text-xs font-bold uppercase tracking-widest text-slate-500 hover:text-white transition-all rounded-md hover:bg-white/5"
          >
            <RefreshCw className={cn("w-4 h-4", isSyncing && "animate-spin")} />
            Sync Vault
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          <div className="text-[10px] uppercase tracking-widest font-bold text-slate-500 px-3 border-b border-slate-800 pb-2 mb-4">Stored Knowledge ({notes.length})</div>
          <div className="px-1 mb-3">
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-3.5 h-3.5 text-slate-600" />
              <input
                type="text"
                placeholder="Search notes..."
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                className="w-full bg-black border border-slate-800 rounded-sm py-2 pl-9 pr-3 text-xs focus:outline-none focus:ring-1 focus:ring-orange-500/50 transition-all font-mono placeholder-slate-700 text-slate-300"
              />
            </div>
          </div>
          {notes.length === 0 && (
            <div className="px-3 py-6 text-sm text-slate-500 italic">No notes ingested yet.</div>
          )}
          {notes.filter(n => !searchQuery || n.title.toLowerCase().includes(searchQuery.toLowerCase())).map((note) => (
            <button
              key={note.fileName}
              onClick={() => handleSelectNote(note)}
              className={cn(
                "w-full text-left p-3 rounded-sm border transition-all group flex items-start gap-3",
                selectedNote?.fileName === note.fileName 
                  ? "bg-[#111] border-l-2 border-l-orange-500 border-y-slate-800 border-r-slate-800 text-slate-300" 
                  : "bg-transparent border-transparent text-slate-500 hover:bg-slate-800/50"
              )}
            >
              <FileText className={cn("w-4 h-4 mt-0.5 shrink-0", selectedNote?.fileName === note.fileName ? "text-orange-500" : "opacity-50")} />
              <div className="flex-1 min-w-0">
                <div className="text-sm font-medium truncate">{note.title}</div>
                <div className="text-[10px] opacity-60 font-mono mt-1">{format(new Date(note.date), 'yyyy-MM-dd HH:mm')}</div>
              </div>
            </button>
          ))}
        </div>

        <div className="p-4 border-t border-slate-800 bg-[#111]">
          <div className="flex items-center gap-3 px-3 py-3 rounded-sm bg-black border border-slate-800">
            <div className="w-8 h-8 rounded-full bg-slate-800 flex items-center justify-center">
              <Shield className="w-4 h-4 text-emerald-500" />
            </div>
            <div className="flex-1 truncate">
              <div className="text-[10px] text-slate-500 uppercase tracking-widest leading-none mb-1">Secure Node</div>
              <div className="text-xs font-mono text-emerald-500 truncate">V_SYNCED</div>
            </div>
          </div>
        </div>
      </aside>

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col bg-[#050505] relative overflow-hidden">
        {/* Top Header - Ingestion Bar */}
        <header className="h-16 border-b border-slate-800 bg-black/60 backdrop-blur-md flex items-center px-8 justify-between z-10">
          <div className="flex-1 max-w-2xl flex flex-col relative">
            <form onSubmit={handleIngest} className="flex items-center gap-2 group">
              <div className="relative flex-1 flex items-center group">
                <Zap className="absolute left-4 w-4 h-4 text-orange-500 opacity-50 group-focus-within:opacity-100 transition-opacity" />
                <input
                  type="text"
                  placeholder="Paste URL (YouTube, TikTok, Instagram, Web) to ingest knowledge..."
                  className="w-full bg-black border border-slate-800 rounded-sm py-2 pl-12 pr-4 text-sm focus:outline-none focus:ring-1 focus:ring-orange-500/50 transition-all font-mono placeholder-slate-700"
                  value={url}
                  onChange={(e) => setUrl(e.target.value)}
                  disabled={loadingNote}
                />
                {loadingNote && (
                  <div className="absolute right-4 flex items-center gap-3">
                    <div className="text-[10px] text-orange-500/70 font-mono animate-pulse">{ingestStatus}</div>
                    <Loader2 className="w-4 h-4 text-orange-500 animate-spin" />
                  </div>
                )}
                {!loadingNote && url && (
                  <button
                    type="submit"
                    className="absolute right-2 px-3 py-1 rounded-sm bg-orange-500 text-black text-[10px] font-bold uppercase tracking-wider hover:bg-orange-400 transition-colors"
                  >
                    Ingest
                  </button>
                )}
              </div>
              <input
                type="file"
                accept=".pdf"
                className="hidden"
                ref={fileInputRef}
                onChange={handleFileUpload}
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={loadingNote}
                className="px-4 py-2 bg-slate-800 border border-slate-700 rounded-sm hover:bg-slate-700 transition-colors text-slate-300 font-mono text-xs disabled:opacity-50 flex items-center gap-2"
                title="Upload PDF Document"
              >
                <Plus className="w-4 h-4" /> PDF
              </button>
            </form>
            
            <AnimatePresence>
              {(error || success) && (
                <motion.div 
                  initial={{ opacity: 0, y: -10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, y: -10 }}
                  className={cn(
                    "absolute top-full left-0 right-0 mt-2 p-2 rounded-sm text-[10px] uppercase tracking-wider font-bold flex items-center gap-2 border",
                    error ? "bg-red-500/10 border-red-500/20 text-red-500" : "bg-emerald-500/10 border-emerald-500/20 text-emerald-500"
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
              <div className={cn(
                "hidden xl:flex items-center gap-2 max-w-xs border rounded-sm px-3 py-2 bg-black font-mono",
                visibleTask.state === 'failed'
                  ? "border-red-500/30 text-red-400"
                  : "border-orange-500/30 text-orange-400"
              )}>
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
                onClick={() => { setShowDashboard(!showDashboard); if (!showDashboard) setSelectedNote(null); }}
                className={cn(
                  "flex items-center gap-2 px-3 py-1.5 text-xs font-bold uppercase tracking-widest transition-all rounded-sm",
                  showDashboard 
                    ? "bg-indigo-500/20 text-indigo-400 border border-indigo-500/50 shadow-[0_0_10px_rgba(99,102,241,0.2)]" 
                    : "text-slate-500 hover:text-white border border-slate-800 hover:border-slate-600 bg-slate-900/50"
                )}
              >
                <Activity className="w-3.5 h-3.5" />
                {showDashboard ? "Exit Status" : "Mission Control"}
              </button>
              <div className="text-right">
                <p className="text-[10px] uppercase text-slate-500 tracking-widest leading-none mb-1">Active Model</p>
                <p className="text-xs font-mono text-white">{activeModel}</p>
              </div>
            </div>
          </div>
        </header>

        <div className="flex-1 flex overflow-hidden p-6 gap-6">
          {/* Note Viewer */}
          <div className="flex-1 overflow-y-auto bg-[#0a0a0a]/90 backdrop-blur-md bg-circuit border border-slate-800 shadow-2xl rounded-sm p-0 scroll-smooth relative">
            <AnimatePresence mode="wait">
              {selectedNote ? (
                <motion.div
                  key={selectedNote.fileName}
                  initial={{ opacity: 0 }}
                  animate={{ opacity: 1 }}
                  exit={{ opacity: 0 }}
                  className="h-full flex flex-col"
                >
                  {/* Toolbar */}
                  <div className="flex items-center justify-between px-6 py-3 border-b border-slate-800 bg-black/50 sticky top-0 z-10 backdrop-blur-md">
                    <div className="flex items-center gap-2">
                      <button 
                        onClick={() => handleAction('summarize')}
                        disabled={!!actionLoading}
                        className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all disabled:opacity-50"
                      >
                        {actionLoading === 'summarize' ? <Loader2 className="w-3 h-3 animate-spin" /> : <Sparkles className="w-3 h-3 text-orange-500" />}
                        Summarize
                      </button>
                      <button 
                        onClick={() => handleAction('deep_dive')}
                        disabled={!!actionLoading}
                        className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all disabled:opacity-50"
                      >
                        {actionLoading === 'deep_dive' ? <Loader2 className="w-3 h-3 animate-spin" /> : <Zap className="w-3 h-3 text-orange-500" />}
                        Deep Dive
                      </button>
                    </div>
                    
                    <button 
                      onClick={() => noteContent && handleCopy(noteContent)}
                      className="p-1.5 rounded-sm hover:bg-slate-800 transition-colors text-slate-500 hover:text-white"
                      title="Copy Markdown"
                    >
                      {copied ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                    </button>
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
                            <h4 className="text-[10px] uppercase tracking-[0.2em] font-black text-orange-500">{actionResult.type}</h4>
                            <button onClick={() => setActionResult(null)} className="text-slate-600 hover:text-white text-xs transition-colors italic">dismiss</button>
                          </div>
                          <div className="prose prose-invert prose-sm max-w-none text-slate-300 font-serif italic leading-relaxed">
                            <ReactMarkdown>{actionResult.content}</ReactMarkdown>
                          </div>
                          <div className="absolute -bottom-px left-0 right-0 h-px bg-gradient-to-r from-transparent via-orange-500/50 to-transparent" />
                        </motion.div>
                      )}
                    </AnimatePresence>

                    {noteContent ? (
                      <div className="prose prose-invert prose-slate max-w-none prose-headings:font-display prose-headings:font-light prose-headings:italic markdown-body">
                        <ReactMarkdown>{noteContent}</ReactMarkdown>
                      </div>
                    ) : (
                      <div className="h-full flex items-center justify-center py-20">
                        <Loader2 className="w-6 h-6 text-slate-700 animate-spin" />
                      </div>
                    )}
                  </div>
                </motion.div>
              ) : showDashboard ? (
                <motion.div
                  key="dashboard"
                  initial={{ opacity: 0, scale: 0.98 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.98 }}
                  className="h-full overflow-y-auto"
                >
                  <SystemDashboard />
                </motion.div>
              ) : (
                <motion.div 
                  key="empty"
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  exit={{ opacity: 0, scale: 0.95 }}
                  className="h-full flex flex-col items-center justify-center text-center max-w-md mx-auto"
                >
                  <div className="w-20 h-20 bg-black border border-slate-800 flex items-center justify-center mb-6 relative">
                    <Brain className="w-8 h-8 text-orange-500" />
                  </div>
                  <h2 className="text-2xl font-display font-light italic mb-3 tracking-tight text-white">Awaiting Input</h2>
                  <p className="text-xs text-slate-500 leading-relaxed mb-8 uppercase tracking-widest">
                    SYSTEM IDLE. INGEST URL OR SELECT EXISTING ENTRY.
                  </p>
                  <div className="grid grid-cols-2 gap-3 w-full">
                    {[
                      { icon: <Zap className="w-4 h-4 text-orange-500" />, label: "Auto Transcribe" },
                      { icon: <Clock className="w-4 h-4 text-slate-400" />, label: "Long-term Recall" },
                      { icon: <Shield className="w-4 h-4 text-emerald-500" />, label: "Secure Storage" },
                      { icon: <Search className="w-4 h-4 text-blue-400" />, label: "AI Search" },
                    ].map((feat, i) => (
                      <div key={i} className="flex flex-col items-center gap-2 p-4 bg-black border border-slate-800 rounded-sm">
                        {feat.icon}
                        <span className="text-[10px] uppercase font-mono text-slate-500">{feat.label}</span>
                      </div>
                    ))}
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* AI Chat Sidebar Area */}
          <section className={cn(
            "transition-all duration-500 ease-in-out flex shadow-2xl relative",
            isChatMinimized ? "h-12 w-[640px] translate-y-[calc(100%-3rem)] absolute bottom-0 right-8 bg-[#111] flex-row" : "w-[640px] bg-[#111] border-l border-slate-800 flex-row"
          )}>
            {!isChatMinimized && (
              <ChatSidebar
                onSelectSession={loadChatSession}
                currentSessionId={currentSessionId}
                onNewSession={handleNewSession}
              />
            )}
            <div className="flex-1 flex flex-col hardware-border border-l border-slate-800">
            {isChatMinimized ? (
              <button 
                onClick={() => setIsChatMinimized(false)}
                className="w-full h-full flex items-center justify-center bg-orange-500 text-black rounded-sm hover:bg-orange-400 transition-colors shadow-[0_0_15px_rgba(249,115,22,0.4)]"
                title="Restore Terminal"
              >
                <Send className="w-5 h-5 -rotate-45" />
              </button>
            ) : (
              <>
                <div className="p-4 border-b border-slate-800 flex items-center justify-between bg-black/40 min-h-[57px]">
                  <div className="flex items-center gap-3">
                    <h2 className="text-xs uppercase text-slate-500 tracking-widest font-bold">Terminal / Chat</h2>
                    <span className="text-[10px] font-mono bg-slate-800 px-2 py-1 text-slate-400 rounded-sm">RAG_ENABLED</span>
                  </div>
                  <button 
                    onClick={() => setIsChatMinimized(true)}
                    className="p-1 hover:bg-slate-800 rounded transition-colors text-slate-500 hover:text-white"
                    title="Minimize"
                  >
                    <ChevronDown className="w-4 h-4" />
                  </button>
                </div>

                <div className="flex-1 overflow-y-auto p-4 space-y-4 font-mono text-sm">
                  {messages.length === 0 && (
                    <div className="text-left text-slate-500">
                      <p>{">"} Ask questions about your ingested knowledge.</p>
                      <p>{">"} Cortex will synthesize answers from your vault.</p>
                    </div>
                  )}
                  {messages.map((msg) => (
                    <div 
                      key={msg.id} 
                      className={cn(
                        "flex flex-col gap-1.5",
                        msg.isAi ? "items-start border-l border-slate-700 pl-4 py-2 bg-slate-900/30" : "items-end"
                      )}
                    >
                      <div className={cn(
                        "text-xs leading-relaxed max-w-[95%]",
                        msg.isAi 
                          ? "text-slate-300 font-mono" 
                          : "bg-orange-500 text-black font-medium py-2 px-3 rounded-sm"
                      )}>
                        {msg.isAi ? <ReactMarkdown>{msg.text}</ReactMarkdown> : msg.text}
                      </div>
                    </div>
                  ))}
                  {isTyping && (
                    <div className="text-orange-500 animate-pulse font-mono text-sm pl-4">
                      {"_"}
                    </div>
                  )}
                  <div ref={chatEndRef} />
                </div>

                <div className="p-4 border-t border-slate-800 bg-[#111]">
                  <form onSubmit={handleChat} className="relative">
                    <input 
                      type="text" 
                      value={chatInput}
                      onChange={(e) => setChatInput(e.target.value)}
                      placeholder="ASK YOUR BRAIN..."
                      className="w-full bg-black border border-slate-800 rounded-sm py-3 pl-4 pr-12 text-sm text-white font-mono placeholder-slate-700 outline-none focus:border-orange-500/50 transition-colors"
                    />
                    <button 
                      type="submit"
                      disabled={!chatInput.trim() || isTyping}
                      className="absolute right-2 top-1/2 -translate-y-1/2 p-2 text-orange-500 hover:text-orange-400 disabled:text-slate-700 transition-colors"
                    >
                      <Send className="w-4 h-4" />
                    </button>
                  </form>
                </div>
              </>
            )}
            </div>
          </section>
        </div>
      </main>
    </div>
  );
}
