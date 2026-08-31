import React, { useCallback } from 'react';
import { AnimatePresence, motion } from 'motion/react';
import SystemDashboard from './components/SystemDashboard';
import { VaultSidebar } from './components/layout/VaultSidebar';
import { IngestionHeader } from './components/layout/IngestionHeader';
import { NoteViewer } from './components/layout/NoteViewer';
import { EmptyWorkspace } from './components/layout/EmptyWorkspace';
import { ChatPanel } from './components/layout/ChatPanel';
import { ActiveQueueOverlay } from './components/layout/ActiveQueueOverlay';

import { useNotes } from './hooks/useNotes';
import { useChat } from './hooks/useChat';
import { useIngest } from './hooks/useIngest';
import { useSystemStatus } from './hooks/useSystemStatus';

export default function App() {
  const {
    activeTasks,
    activeModel,
    isSyncing,
    showDashboard,
    setShowDashboard,
    theme,
    toggleTheme,
    fetchOperationStatus,
    handleSync,
    visibleTask,
    visibleTaskProgress,
  } = useSystemStatus();

  const {
    notes,
    selectedNote,
    setSelectedNote,
    noteContent,
    searchQuery,
    setSearchQuery,
    actionLoading,
    actionResult,
    setActionResult,
    copied,
    fetchNotes,
    handleSelectNote,
    handleSelectNoteByName,
    handleAction,
    handleSaveTasks,
    handleGenerateWeeklyBrief,
    handleCopy,
    closeNote,
  } = useNotes({
    onError: (msg) => ingest.setError(msg),
    onSuccess: (msg) => {
      ingest.setSuccess(msg);
      setTimeout(() => ingest.setSuccess(null), 3000);
    },
    onLoading: (isLoading, text) => {
      ingest.setLoadingNote(isLoading);
      ingest.setIngestStatus(text || null);
    },
  });

  const ingest = useIngest({
    onNoteIngested: (note) => {
      setShowDashboard(false);
      handleSelectNote(note);
    },
    onRefreshNotes: fetchNotes,
    onRefreshStatus: fetchOperationStatus,
  });

  const chat = useChat({
    selectedNote,
    onError: (msg) => ingest.setError(msg),
    onSuccess: (msg) => {
      ingest.setSuccess(msg);
      setTimeout(() => ingest.setSuccess(null), 3000);
      fetchNotes();
    },
  });

  const onSelectNoteWrapper = useCallback(
    (note: any) => {
      setShowDashboard(false);
      handleSelectNote(note);
    },
    [handleSelectNote, setShowDashboard]
  );

  const onSelectNoteByNameWrapper = useCallback(
    (name: string) => {
      setShowDashboard(false);
      handleSelectNoteByName(name);
    },
    [handleSelectNoteByName, setShowDashboard]
  );

  return (
    <div className="flex h-screen w-full bg-[#050505] font-sans text-slate-300 overflow-hidden p-0 sm:p-2">
      {/* Sidebar - Vault Explorer */}
      <VaultSidebar
        notes={notes}
        selectedNote={selectedNote}
        searchQuery={searchQuery}
        isSyncing={isSyncing}
        onSearchChange={setSearchQuery}
        onSelectNote={onSelectNoteWrapper}
        onSync={handleSync}
      />

      {/* Main Content Area */}
      <main className="flex-1 flex flex-col bg-[#050505] relative overflow-hidden">
        {/* Top Header - Ingestion Bar & Status */}
        <IngestionHeader
          url={ingest.url}
          loadingNote={ingest.loadingNote}
          ingestStatus={ingest.ingestStatus}
          error={ingest.error}
          success={ingest.success}
          isDragging={ingest.isDragging}
          isRecording={ingest.isRecording}
          fileInputRef={ingest.fileInputRef}
          visibleTask={visibleTask}
          visibleTaskProgress={visibleTaskProgress}
          theme={theme}
          showDashboard={showDashboard}
          activeModel={activeModel}
          onUrlChange={ingest.setUrl}
          onIngest={ingest.handleIngest}
          onFileUpload={ingest.handleFileUpload}
          onDragOver={ingest.handleDragOver}
          onDragLeave={ingest.handleDragLeave}
          onDrop={ingest.handleDrop}
          onToggleRecording={ingest.toggleRecording}
          onToggleTheme={toggleTheme}
          onToggleDashboard={() => {
            setShowDashboard((prev) => !prev);
            if (!showDashboard) setSelectedNote(null);
          }}
        />

        {/* Workspace Body */}
        <div className="flex-1 flex overflow-hidden p-6 gap-6">
          <div className="flex-1 overflow-y-auto bg-[#0a0a0a]/90 backdrop-blur-md bg-circuit border border-slate-800 shadow-2xl rounded-sm p-0 scroll-smooth relative">
            <AnimatePresence mode="wait">
              {selectedNote ? (
                <NoteViewer
                  selectedNote={selectedNote}
                  noteContent={noteContent}
                  actionLoading={actionLoading}
                  actionResult={actionResult}
                  copied={copied}
                  onAction={handleAction}
                  onDiscuss={() => {
                    chat.setIsChatMinimized(false);
                    chat.setUseActiveNoteContext(true);
                  }}
                  onCopy={handleCopy}
                  onClose={closeNote}
                  onSaveTasks={handleSaveTasks}
                  onDismissActionResult={() => setActionResult(null)}
                />
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
                <EmptyWorkspace
                  notes={notes}
                  loadingNote={ingest.loadingNote}
                  onSelectNote={onSelectNoteWrapper}
                  onSelectNoteByName={onSelectNoteByNameWrapper}
                  onCompileComplete={fetchNotes}
                  onGenerateWeeklyBrief={handleGenerateWeeklyBrief}
                />
              )}
            </AnimatePresence>
          </div>

          {/* AI Terminal / Chat Panel */}
          <ChatPanel
            messages={chat.messages}
            chatInput={chat.chatInput}
            isTyping={chat.isTyping}
            isChatMinimized={chat.isChatMinimized}
            useActiveNoteContext={chat.useActiveNoteContext}
            selectedNote={selectedNote}
            chatEndRef={chat.chatEndRef}
            onChatInputChange={chat.setChatInput}
            onChatSubmit={chat.handleChat}
            onToggleMinimize={chat.setIsChatMinimized}
            onToggleActiveNoteContext={chat.setUseActiveNoteContext}
            onPromoteToWiki={chat.handlePromoteToWiki}
          />
        </div>
      </main>

      {/* Floating Active Task Queue Realtime Cards */}
      <ActiveQueueOverlay activeTasks={activeTasks} />
    </div>
  );
}
