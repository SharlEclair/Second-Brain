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
  CheckCircle2
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import ReactMarkdown from 'react-markdown';
import { format } from 'date-fns';
import { cn } from './lib/utils';

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

export default function App() {
  const [url, setUrl] = useState('');
  const [loadingNote, setLoadingNote] = useState(false);
  const [notes, setNotes] = useState<Note[]>([]);
  const [selectedNote, setSelectedNote] = useState<Note | null>(null);
  const [noteContent, setNoteContent] = useState<string | null>(null);
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [chatInput, setChatInput] = useState('');
  const [isSyncing, setIsSyncing] = useState(false);
  const [isTyping, setIsTyping] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  
  const chatEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetchNotes();
  }, []);

  useEffect(() => {
    if (chatEndRef.current) {
      chatEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages]);

  const fetchNotes = async () => {
    try {
      const res = await fetch('/api/notes');
      const data = await res.json();
      setNotes(data);
    } catch (e) {
      console.error("Failed to fetch notes", e);
    }
  };

  const handleIngest = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!url) return;
    
    setLoadingNote(true);
    setError(null);
    setSuccess(null);

    try {
      const res = await fetch('/api/ingest', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ url })
      });
      const data = await res.json();
      if (data.note) {
        await fetchNotes();
        handleSelectNote(data.note);
        setUrl('');
        setSuccess(data.status === 'existing' ? 'Note already exists' : 'Note successfully ingested');
        setTimeout(() => setSuccess(null), 3000);
      } else if (data.error) {
        setError(data.error);
      }
    } catch (e: any) {
      console.error("Ingestion failed", e);
      setError("Network error or server is down");
    } finally {
      setLoadingNote(false);
    }
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
        body: JSON.stringify({ message: userMsg.text })
      });
      const data = await res.json();
      
      if (data.response) {
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

  return (
    <div className="flex h-screen w-full bg-[#050505] font-sans text-slate-300 overflow-hidden p-0 sm:p-2">
      {/* Sidebar - Vault Explorer */}
      <aside className="w-80 flex flex-col border-r border-slate-800 bg-[#111]">
        <div className="p-6 border-b border-slate-800 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-sm bg-orange-500/10 flex items-center justify-center border border-orange-500/20">
              <Brain className="w-5 h-5 text-orange-500" />
            </div>
            <h1 className="font-display font-light italic text-xl tracking-tight text-white">BRAIN_VAULT</h1>
          </div>
          <button 
            onClick={handleSync}
            disabled={isSyncing}
            className="p-2 rounded-sm hover:bg-slate-800 transition-colors text-slate-500 hover:text-white"
          >
            <RefreshCw className={cn("w-4 h-4", isSyncing && "animate-spin")} />
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-2">
          <div className="text-[10px] uppercase tracking-widest font-bold text-slate-500 px-3 border-b border-slate-800 pb-2 mb-4">Stored Knowledge</div>
          {notes.length === 0 && (
            <div className="px-3 py-6 text-sm text-slate-500 italic">No notes ingested yet.</div>
          )}
          {notes.map((note) => (
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
        <header className="h-16 border-b border-slate-800 bg-[#050505] flex items-center px-8 justify-between z-10">
          <div className="flex-1 max-w-2xl flex flex-col relative">
            <form onSubmit={handleIngest} className="flex items-center relative group">
              <Zap className="absolute left-4 w-4 h-4 text-orange-500 opacity-50 group-focus-within:opacity-100 transition-opacity" />
              <input 
                type="text" 
                placeholder="Paste URL (YouTube, TikTok, Instagram) to ingest knowledge..."
                className="w-full bg-black border border-slate-800 rounded-sm py-2 pl-12 pr-4 text-sm focus:outline-none focus:ring-1 focus:ring-orange-500/50 transition-all font-mono placeholder-slate-700"
                value={url}
                onChange={(e) => setUrl(e.target.value)}
                disabled={loadingNote}
              />
              {loadingNote && (
                <div className="absolute right-4 flex items-center gap-2">
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
            <div className="h-4 w-px bg-slate-800" />
            <div className="text-right">
              <p className="text-[10px] uppercase text-slate-500 tracking-widest leading-none mb-1">Active Model</p>
              <p className="text-xs font-mono text-white">GEMINI-FLASH</p>
            </div>
          </div>
        </header>

        <div className="flex-1 flex overflow-hidden p-6 gap-6">
          {/* Note Viewer */}
          <div className="flex-1 overflow-y-auto bg-[#111] border border-slate-800 rounded-sm p-6 scroll-smooth">
            <AnimatePresence mode="wait">
              {!selectedNote ? (
                <motion.div 
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
              ) : (
                <motion.div 
                  key={selectedNote.fileName}
                  initial={{ opacity: 0, y: 10 }}
                  animate={{ opacity: 1, y: 0 }}
                  className="max-w-3xl mx-auto"
                >
                  {!noteContent ? (
                    <div className="flex items-center justify-center py-20">
                      <Loader2 className="w-6 h-6 text-orange-500 animate-spin" />
                    </div>
                  ) : (
                    <div className="markdown-body">
                      <ReactMarkdown>{noteContent}</ReactMarkdown>
                    </div>
                  )}
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* AI Chat Sidebar */}
          <section className="w-[400px] border border-slate-800 bg-black rounded-sm flex flex-col">
            <div className="p-4 border-b border-slate-800 flex items-center justify-between">
              <h2 className="text-xs uppercase text-slate-500 tracking-widest font-bold">Terminal / Chat</h2>
              <span className="text-[10px] font-mono bg-slate-800 px-2 py-1 text-slate-400 rounded-sm">RAG_ENABLED</span>
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
          </section>
        </div>
      </main>
    </div>
  );
}
