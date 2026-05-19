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
  Activity,
  X,
  Mic,
  MicOff,
  CheckSquare
} from 'lucide-react';
import { motion, AnimatePresence } from 'motion/react';
import ReactMarkdown from 'react-markdown';
import { format } from 'date-fns';
import { cn } from './lib/utils';
import SystemDashboard from './components/SystemDashboard';
import ChatSidebar from './components/ChatSidebar';
import EventsWidget from './components/EventsWidget';
import SuggestionsWidget from './components/SuggestionsWidget';
import SerendipityWidget from './components/SerendipityWidget';
import VaultGraph from './components/VaultGraph';
import ActivityHeatmap from './components/ActivityHeatmap';
import { LibraryDirectory } from './components/LibraryDirectory';



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
  const [rawCount, setRawCount] = useState<number>(0);
  const [isCompiling, setIsCompiling] = useState(false);
  const [useActiveNoteContext, setUseActiveNoteContext] = useState(false);
  const [isDragging, setIsDragging] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [mediaRecorder, setMediaRecorder] = useState<MediaRecorder | null>(null);
  
  const chatEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    fetchNotes();
    fetchOperationStatus();
    fetchRawCount();
    fetch('/api/config').then(r => r.json()).then(d => {
      if (d.model) setActiveModel(d.model.replace('models/', '').toUpperCase());
    }).catch(() => {});

    const interval = setInterval(() => {
      fetchOperationStatus();
      fetchRawCount();
    }, 2000);
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

  const fetchRawCount = async () => {
    try {
      const res = await fetch('/api/raw_count');
      const data = await res.json();
      setRawCount(data.count || 0);
    } catch (e) {
      console.error("Failed to fetch raw count", e);
    }
  };

  const uploadFileObj = async (file: File) => {
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

      setSuccess('File successfully ingested');
      fetchNotes();
      setUrl('');
      if (data.note) {
        handleSelectNote(data.note);
      }
    } catch (err: any) {
      setError(err.message || "Failed to process file.");
    } finally {
      setLoadingNote(false);
      setIngestStatus(null);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  };

  const handleFileUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;
    await uploadFileObj(file);
  };

  const handleDragOver = (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  };

  const handleDragLeave = () => {
    setIsDragging(false);
  };

  const handleDrop = async (e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(false);
    
    const file = e.dataTransfer.files?.[0];
    if (!file) return;
    await uploadFileObj(file);
  };

  const startRecording = async () => {
    try {
      const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
      const recorder = new MediaRecorder(stream);
      const chunks: Blob[] = [];

      recorder.ondataavailable = (e) => {
        if (e.data.size > 0) {
          chunks.push(e.data);
        }
      };

      recorder.onstop = async () => {
        const audioBlob = new Blob(chunks, { type: 'audio/wav' });
        const file = new File([audioBlob], `voice_capture_${Date.now()}.wav`, { type: 'audio/wav' });
        await uploadFileObj(file);
        stream.getTracks().forEach(track => track.stop());
      };

      recorder.start();
      setMediaRecorder(recorder);
      setIsRecording(true);
    } catch (err) {
      console.error("Failed to start voice recording", err);
      setError("Failed to access microphone.");
    }
  };

  const stopRecording = () => {
    if (mediaRecorder && isRecording) {
      mediaRecorder.stop();
      setIsRecording(false);
      setMediaRecorder(null);
    }
  };

  const toggleRecording = () => {
    if (isRecording) {
      stopRecording();
    } else {
      startRecording();
    }
  };


  const handleCompileInbox = async () => {
    if (rawCount === 0 || isCompiling) return;
    setIsCompiling(true);
    try {
      const res = await fetch('/api/compile', { method: 'POST' });
      const data = await res.json();
      if (data.status === 'success') {
        alert(`Compiled ${data.compiled_count} items from Inbox.`);
        setRawCount(0);
        fetchNotes();
      } else {
        alert("Compile failed: " + data.detail);
      }
    } catch (e: any) {
      alert("Compile Error: " + e.message);
    } finally {
      setIsCompiling(false);
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
        headers['X-Stream'] = 'false';
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

  const handleAction = async (type: 'summarize' | 'deep_dive' | 'extract_tasks') => {
    if (!selectedNote) return;
    setActionLoading(type);
    setActionResult(null);
    
    try {
      const res = await fetch(`/api/notes/${selectedNote.fileName}/${type}`, { method: 'POST' });
      const data = await res.json();
      setActionResult({ 
        type: type === 'summarize' ? 'Quick Summary' : type === 'deep_dive' ? 'Deep Dive Analysis' : 'Actionable Tasks', 
        content: data.summary || data.deep_dive || data.tasks
      });
    } catch (e) {
      setError("Action failed");
    } finally {
      setActionLoading(null);
    }
  };

  const handleSaveTasks = async (tasksContent: string) => {
    if (!selectedNote) return;
    try {
      const res = await fetch(`/api/notes/${selectedNote.fileName}/append_tasks`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({ tasks: tasksContent })
      });
      const data = await res.json();
      if (res.ok) {
        setSuccess('Tasks appended to note!');
        setTimeout(() => setSuccess(null), 3000);
        // Refresh note content
        const contentRes = await fetch(`/api/notes/${selectedNote.fileName}`);
        const text = await contentRes.text();
        setNoteContent(text);
        setActionResult(null);
      } else {
        setError(data.detail || 'Failed to append tasks');
      }
    } catch (e) {
      setError('Error appending tasks');
    }
  };  const handleGenerateWeeklyBrief = async () => {
    setLoadingNote(true);
    setError(null);
    setSuccess(null);
    setIngestStatus('Compiling Weekly Brief...');
    try {
      const res = await fetch('/api/weekly_brief');
      const data = await res.json();
      if (!res.ok) {
        throw new Error(data.detail || 'Failed to generate weekly brief');
      }
      setSuccess('Weekly Brief successfully compiled!');
      fetchNotes();
      if (data.note) {
        handleSelectNote(data.note);
      }
    } catch (err: any) {
      setError(err.message || 'Failed to generate weekly brief');
    } finally {
      setLoadingNote(false);
      setIngestStatus(null);
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

  const handleSelectNoteByName = (noteName: string) => {
    const found = notes.find(n => n.title === noteName || n.fileName.endsWith(noteName + '.md') || n.fileName.includes('/' + noteName + '.md'));
    if (found) {
      handleSelectNote(found);
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
        body: JSON.stringify({ 
          message: userMsg.text, 
          session_id: currentSessionId,
          note_context: useActiveNoteContext && selectedNote ? selectedNote.fileName : undefined
        })
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
        throw new Error(data.detail || data.error || "Unknown AI error");
      }
    } catch (e: any) {
      console.error("Chat failed", e);
      setError(`Chat failed: ${e.message}`);
    } finally {
      setIsTyping(false);
    }
  };

  const handlePromoteToWiki = async (msg: ChatMessage) => {
    const title = prompt("Enter a title for this new Synthesis note:");
    if (!title) return;
    try {
      const res = await fetch('/api/save_answer', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ title, content: msg.text })
      });
      const data = await res.json();
      if (data.status === 'success') {
        alert("Synthesized into Wiki: " + data.fileName);
      } else {
        alert("Failed to promote: " + (data.detail || data.error));
      }
    } catch (e: any) {
      alert("Error: " + e.message);
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
            <form 
              onSubmit={handleIngest} 
              onDragOver={handleDragOver}
              onDragLeave={handleDragLeave}
              onDrop={handleDrop}
              className={cn(
                "flex items-center gap-2 group transition-all duration-200 border rounded-sm p-1",
                isDragging 
                  ? "border-orange-500 bg-orange-500/5 ring-1 ring-orange-500/30" 
                  : "border-transparent bg-transparent"
              )}
            >
              <div className="relative flex-1 flex items-center group">
                <Zap className="absolute left-4 w-4 h-4 text-orange-500 opacity-50 group-focus-within:opacity-100 transition-opacity" />
                <input
                  type="text"
                  placeholder={isDragging ? "Drop file here to ingest..." : "Paste URL (YouTube, TikTok, Instagram, Web) or drop file..."}
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
                accept=".pdf,.txt,.md,.mp3,.wav,.m4a,.ogg,.aac,.png,.jpg,.jpeg,.webp"
                className="hidden"
                ref={fileInputRef}
                onChange={handleFileUpload}
              />
              <button
                type="button"
                onClick={() => fileInputRef.current?.click()}
                disabled={loadingNote}
                className="px-4 py-2 bg-slate-800 border border-slate-700 rounded-sm hover:bg-slate-700 transition-colors text-slate-300 font-mono text-xs disabled:opacity-50 flex items-center gap-2"
                title="Upload Document, Audio, or Image"
              >
                <Plus className="w-4 h-4" /> Upload
              </button>
              
              <button
                type="button"
                onClick={toggleRecording}
                disabled={loadingNote}
                className={cn(
                  "px-4 py-2 border rounded-sm transition-all font-mono text-xs flex items-center gap-2",
                  isRecording 
                    ? "bg-red-500/20 border-red-500 text-red-500 animate-pulse font-bold" 
                    : "bg-slate-800 border-slate-700 hover:bg-slate-700 text-slate-300"
                )}
                title={isRecording ? "Stop Recording" : "Record Voice Note"}
              >
                {isRecording ? <MicOff className="w-4 h-4" /> : <Mic className="w-4 h-4 text-orange-500" />}
                {isRecording ? "REC..." : "REC"}
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

              {rawCount > 0 && (
                <motion.button
                  initial={{ scale: 0.9, opacity: 0 }}
                  animate={{ scale: 1, opacity: 1 }}
                  whileHover={{ scale: 1.05 }}
                  whileTap={{ scale: 0.95 }}
                  onClick={handleCompileInbox}
                  disabled={isCompiling}
                  className="ml-4 flex items-center gap-2 px-3 py-1.5 bg-orange-500/10 hover:bg-orange-500/20 border border-orange-500/50 rounded-sm text-orange-400 text-[10px] uppercase font-bold tracking-widest transition-colors relative overflow-hidden"
                >
                  {isCompiling ? (
                    <Loader2 className="w-3.5 h-3.5 animate-spin" />
                  ) : (
                    <div className="flex items-center gap-2">
                      <span className="w-2 h-2 rounded-full bg-orange-500 animate-pulse" />
                      Compile Inbox ({rawCount})
                    </div>
                  )}
                  {isCompiling && (
                    <motion.div
                      className="absolute inset-0 bg-orange-500/20"
                      initial={{ x: "-100%" }}
                      animate={{ x: "100%" }}
                      transition={{ repeat: Infinity, duration: 1, ease: "linear" }}
                    />
                  )}
                </motion.button>
              )}
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
                      <button 
                        onClick={() => handleAction('extract_tasks')}
                        disabled={!!actionLoading}
                        className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all disabled:opacity-50"
                      >
                        {actionLoading === 'extract_tasks' ? <Loader2 className="w-3 h-3 animate-spin" /> : <CheckSquare className="w-3 h-3 text-orange-500" />}
                        Extract Tasks
                      </button>
                      <button 
                        onClick={() => {
                          setIsChatMinimized(false);
                          setUseActiveNoteContext(true);
                        }}
                        className="flex items-center gap-2 px-3 py-1.5 rounded-sm bg-slate-900 border border-slate-800 text-[10px] uppercase font-bold text-slate-400 hover:text-white hover:border-slate-600 transition-all"
                      >
                        <Brain className="w-3 h-3 text-orange-500 animate-pulse" />
                        Discuss
                      </button>
                    </div>
                    
                    <div className="flex items-center gap-2">
                      <button 
                        onClick={() => noteContent && handleCopy(noteContent)}
                        className="p-1.5 rounded-sm hover:bg-slate-800 transition-colors text-slate-500 hover:text-white"
                        title="Copy Markdown"
                      >
                        {copied ? <Check className="w-4 h-4 text-emerald-500" /> : <Copy className="w-4 h-4" />}
                      </button>
                      <button 
                        onClick={() => setSelectedNote(null)}
                        className="p-1.5 rounded-sm hover:bg-red-500/20 hover:text-red-400 transition-colors text-slate-500"
                        title="Close Note"
                      >
                        <X className="w-4 h-4" />
                      </button>
                    </div>
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
                            <div className="flex items-center gap-3">
                              {actionResult.type === 'Actionable Tasks' && (
                                <button
                                  onClick={() => handleSaveTasks(actionResult.content)}
                                  className="text-[9px] uppercase font-bold text-emerald-400 hover:text-emerald-300 transition-colors border border-emerald-500/30 px-2 py-0.5 rounded-sm bg-emerald-500/10"
                                >
                                  Append to Note
                                </button>
                              )}
                              <button onClick={() => setActionResult(null)} className="text-slate-600 hover:text-white text-xs transition-colors italic">dismiss</button>
                            </div>
                          </div>
                          <div className="prose prose-invert prose-sm max-w-none text-slate-300 font-serif italic leading-relaxed">
                            <ReactMarkdown>{actionResult.content}</ReactMarkdown>
                          </div>
                          <div className="absolute -bottom-px left-0 right-0 h-px bg-gradient-to-r from-transparent via-orange-500/50 to-transparent" />
                        </motion.div>
                      )}
                    </AnimatePresence>

                    {noteContent ? (
                      <div className="flex flex-col gap-6">
                        {(() => {
                          let processedContent = noteContent;
                          let frontmatter: Record<string, string> = {};
                          
                          if (processedContent.startsWith('---\n')) {
                            const endIdx = processedContent.indexOf('\n---\n', 4);
                            if (endIdx !== -1) {
                              const fmString = processedContent.substring(4, endIdx);
                              fmString.split('\n').forEach(line => {
                                const colonIdx = line.indexOf(':');
                                if (colonIdx !== -1) {
                                  frontmatter[line.substring(0, colonIdx).trim()] = line.substring(colonIdx + 1).trim();
                                }
                              });
                              processedContent = processedContent.substring(endIdx + 5);
                            }
                          }

                          processedContent = processedContent.replace(/\[\[(.*?)\]\]/g, '**`$1`**');

                          return (
                            <>
                              {Object.keys(frontmatter).length > 0 && (
                                <div className="flex flex-wrap gap-2 p-4 bg-[#111] border border-slate-800 rounded-sm">
                                  {Object.entries(frontmatter).map(([k, v]) => (
                                    <div key={k} className="flex items-center gap-2 bg-black px-2 py-1 rounded-sm border border-slate-800">
                                      <span className="text-[10px] uppercase text-slate-500 font-bold tracking-wider">{k}</span>
                                      <span className="text-xs text-slate-300 font-mono">{v}</span>
                                    </div>
                                  ))}
                                </div>
                              )}
                              <div className="prose prose-invert prose-slate max-w-none prose-headings:font-display prose-headings:font-light prose-headings:italic markdown-body">
                                <ReactMarkdown>{processedContent}</ReactMarkdown>
                              </div>
                            </>
                          );
                        })()}
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
                  className="h-full flex flex-col items-center justify-center w-full"
                >
                  <div className="w-full h-full overflow-y-auto py-12 flex flex-col items-center">
                    <div className="flex flex-col items-center justify-center text-center max-w-md mx-auto mb-12 shrink-0">
                      <div className="w-20 h-20 bg-black border border-slate-800 flex items-center justify-center mb-6 relative">
                        <Brain className="w-8 h-8 text-orange-500" />
                      </div>
                      <h2 className="text-2xl font-display font-light italic mb-3 tracking-tight text-white">Awaiting Input</h2>
                      <p className="text-xs text-slate-500 leading-relaxed mb-8 uppercase tracking-widest">
                        SYSTEM IDLE. INGEST URL OR SELECT EXISTING ENTRY.
                      </p>
                    </div>

                    <div className="w-full max-w-5xl mx-auto px-8 mb-6">
                      <VaultGraph onSelectNote={handleSelectNoteByName} />
                    </div>

                    <div className="w-full max-w-5xl mx-auto px-8 grid grid-cols-1 md:grid-cols-4 gap-6">
                      <div className="md:col-span-1 space-y-6">
                        <LibraryDirectory onSelectCategory={handleSelectNoteByName} />
                        <SerendipityWidget onSelectNote={handleSelectNote} />
                        <EventsWidget onSelectEvent={handleSelectNote} />
                        
                        <div className="bg-[#0a0a0a] border border-slate-800 p-4 rounded-sm space-y-3">
                          <div className="flex items-center gap-2">
                            <Sparkles className="w-4 h-4 text-indigo-400 animate-pulse" />
                            <h4 className="text-[10px] font-mono uppercase tracking-widest text-slate-300">Weekly Intelligence</h4>
                          </div>
                          <p className="text-[10px] text-slate-500 font-mono leading-relaxed">
                            Aggregate notes and learning materials ingested over the past 7 days into a structured weekly brief.
                          </p>
                          <button
                            onClick={handleGenerateWeeklyBrief}
                            disabled={loadingNote}
                            className="w-full py-2 bg-indigo-500/10 border border-indigo-500/30 hover:border-indigo-500 text-indigo-400 hover:text-white font-mono text-[10px] uppercase tracking-wider transition-all rounded-sm flex items-center justify-center gap-2"
                          >
                            {loadingNote ? <Loader2 className="w-3 h-3 animate-spin" /> : <Plus className="w-3.5 h-3.5" />}
                            Generate Weekly Brief
                          </button>
                        </div>
                      </div>
                      <div className="md:col-span-3 space-y-6">
                        <SuggestionsWidget onSelectSuggestion={handleSelectNote} />
                        <ActivityHeatmap notes={notes} />

                        <div className="grid grid-cols-2 md:grid-cols-4 gap-3 w-full mt-6">
                          {[
                            { icon: <Zap className="w-4 h-4 text-orange-500" />, label: "Auto Transcribe" },
                            { icon: <Clock className="w-4 h-4 text-slate-400" />, label: "Long-term Recall" },
                            { icon: <Shield className="w-4 h-4 text-emerald-500" />, label: "Secure Storage" },
                            { icon: <Search className="w-4 h-4 text-blue-400" />, label: "AI Search" },
                          ].map((feat, i) => (
                            <div key={i} className="flex flex-col items-center gap-2 p-4 bg-[#111] border border-slate-800 hover:border-slate-700 transition-colors rounded-sm group">
                              {feat.icon}
                              <span className="text-[10px] uppercase font-mono text-slate-500 group-hover:text-slate-400 transition-colors">{feat.label}</span>
                            </div>
                          ))}
                        </div>
                      </div>
                    </div>
                  </div>
                </motion.div>
              )}
            </AnimatePresence>
          </div>

          {/* AI Chat Sidebar Area */}
          <AnimatePresence>
            {!isChatMinimized ? (
              <motion.section 
                initial={{ x: 400 }}
                animate={{ x: 0 }}
                exit={{ x: 400 }}
                className="w-[400px] shadow-2xl relative bg-[#111] border-l border-slate-800 flex flex-col z-20 shrink-0"
              >
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
                        onChange={(e) => setUseActiveNoteContext(e.target.checked)}
                        className="rounded border-slate-800 bg-black text-orange-500 focus:ring-0 focus:ring-offset-0 w-3 h-3"
                      />
                      <span className="text-[9px] uppercase font-mono text-slate-500 font-bold hover:text-slate-400 transition-colors">Focus Chat</span>
                    </label>
                  </div>
                )}

                <div className="flex-1 overflow-y-auto p-4 space-y-4 font-mono text-sm relative">
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
                      {msg.isAi && (
                        <button
                          onClick={() => handlePromoteToWiki(msg)}
                          className="mt-2 text-[10px] uppercase font-bold tracking-widest text-orange-500/70 hover:text-orange-500 border border-orange-500/20 hover:border-orange-500/50 px-2 py-1 rounded-sm transition-all"
                        >
                          Promote to Wiki Article
                        </button>
                      )}
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
              </motion.section>
            ) : (
              <motion.button
                initial={{ scale: 0 }}
                animate={{ scale: 1 }}
                onClick={() => setIsChatMinimized(false)}
                className="fixed bottom-8 right-8 w-14 h-14 bg-orange-500 text-black rounded-full flex items-center justify-center hover:bg-orange-400 transition-transform hover:scale-110 shadow-[0_0_15px_rgba(249,115,22,0.4)] z-50 cursor-pointer"
                title="Restore Terminal"
              >
                <Send className="w-5 h-5 -rotate-45" />
              </motion.button>
            )}
          </AnimatePresence>
        </div>
      </main>

      {/* Floating Active Operations Queue Widget */}
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
                <span className="text-[10px] uppercase font-bold text-white">Active Queue ({activeTasks.length})</span>
              </div>
              <span className="text-[9px] text-slate-500">REALTIME</span>
            </div>
            
            <div className="space-y-3">
              {activeTasks.slice(0, 3).map((task) => (
                <div key={task.task_id} className="text-xs">
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
                  <div className="text-[9px] text-slate-500 italic mt-1 truncate">{task.status}...</div>
                </div>
              ))}
            </div>
          </motion.div>
        )}
      </AnimatePresence>
    </div>
  );
}
