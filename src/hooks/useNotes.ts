import { useState, useCallback, useRef, useEffect } from 'react';
import { Note, ActionResult, NoteActionType } from '../types';
import { notesApi } from '../services/api';

interface UseNotesOptions {
  onError?: (msg: string) => void;
  onSuccess?: (msg: string) => void;
  onLoading?: (isLoading: boolean, statusText?: string | null) => void;
}

export function useNotes(options: UseNotesOptions = {}) {
  const optionsRef = useRef(options);
  optionsRef.current = options;

  const [notes, setNotes] = useState<Note[]>([]);
  const [selectedNote, setSelectedNote] = useState<Note | null>(null);
  const [noteContent, setNoteContent] = useState<string | null>(null);
  const [searchQuery, setSearchQuery] = useState('');
  const [actionLoading, setActionLoading] = useState<string | null>(null);
  const [actionResult, setActionResult] = useState<ActionResult | null>(null);
  const [copied, setCopied] = useState(false);

  const fetchNotes = useCallback(async () => {
    try {
      const data = await notesApi.getNotes();
      setNotes(data);
    } catch (e: any) {
      console.error('Failed to fetch notes', e);
      optionsRef.current.onError?.(e.message || 'Failed to fetch notes');
    }
  }, []);

  useEffect(() => {
    fetchNotes();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handleSelectNote = useCallback(async (note: Note) => {
    setSelectedNote(note);
    setNoteContent(null);
    try {
      const data = await notesApi.getNoteContent(note.fileName);
      setNoteContent(data);
    } catch (e: any) {
      console.error('Failed to fetch note content', e);
      optionsRef.current.onError?.(e.message || 'Failed to fetch note content');
    }
  }, []);

  const handleSelectNoteByName = useCallback((noteName: string) => {
    setNotes((currentNotes) => {
      const found = currentNotes.find(
        (n) =>
          n.title === noteName ||
          n.fileName.endsWith(noteName + '.md') ||
          n.fileName.includes('/' + noteName + '.md')
      );
      if (found) {
        handleSelectNote(found);
      }
      return currentNotes;
    });
  }, [handleSelectNote]);

  const handleAction = useCallback(async (type: NoteActionType) => {
    if (!selectedNote) return;
    setActionLoading(type);
    setActionResult(null);

    try {
      const data = await notesApi.performAction(selectedNote.fileName, type);
      const titleMap: Record<NoteActionType, string> = {
        summarize: 'Quick Summary',
        deep_dive: 'Deep Dive Analysis',
        extract_tasks: 'Actionable Tasks',
      };
      setActionResult({
        type: titleMap[type],
        content: data.summary || data.deep_dive || data.tasks || '',
      });
    } catch (e: any) {
      optionsRef.current.onError?.(e.message || 'Action failed');
    } finally {
      setActionLoading(null);
    }
  }, [selectedNote]);

  const handleSaveTasks = useCallback(async (tasksContent: string) => {
    if (!selectedNote) return;
    try {
      await notesApi.appendTasks(selectedNote.fileName, tasksContent);
      optionsRef.current.onSuccess?.('Tasks appended to note!');
      const text = await notesApi.getNoteContent(selectedNote.fileName);
      setNoteContent(text);
      setActionResult(null);
    } catch (e: any) {
      optionsRef.current.onError?.(e.message || 'Error appending tasks');
    }
  }, [selectedNote]);

  const handleGenerateWeeklyBrief = useCallback(async () => {
    optionsRef.current.onLoading?.(true, 'Compiling Weekly Brief...');
    try {
      const data = await notesApi.generateWeeklyBrief();
      optionsRef.current.onSuccess?.('Weekly Brief successfully compiled!');
      await fetchNotes();
      if (data.note) {
        handleSelectNote(data.note);
      }
    } catch (err: any) {
      optionsRef.current.onError?.(err.message || 'Failed to generate weekly brief');
    } finally {
      optionsRef.current.onLoading?.(false, null);
    }
  }, [fetchNotes, handleSelectNote]);

  const handleCopy = useCallback((text: string) => {
    navigator.clipboard.writeText(text);
    setCopied(true);
    setTimeout(() => setCopied(false), 2000);
  }, []);

  const closeNote = useCallback(() => {
    setSelectedNote(null);
    setNoteContent(null);
    setActionResult(null);
  }, []);

  return {
    notes,
    setNotes,
    selectedNote,
    setSelectedNote,
    noteContent,
    setNoteContent,
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
  };
}
