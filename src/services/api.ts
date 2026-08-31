/**
 * Centralized API client service for Second Brain.
 */
import { Note, NoteActionType, OperationTask } from '../types';

export const notesApi = {
  async getNotes(): Promise<Note[]> {
    const res = await fetch('/api/notes');
    if (!res.ok) throw new Error('Failed to fetch notes');
    return res.json();
  },

  async getNoteContent(fileName: string): Promise<string> {
    const res = await fetch(`/api/notes/${fileName}`);
    if (!res.ok) throw new Error(`Failed to fetch note content for ${fileName}`);
    return res.text();
  },

  async performAction(
    fileName: string,
    type: NoteActionType
  ): Promise<{ summary?: string; deep_dive?: string; tasks?: string; model?: string }> {
    const res = await fetch(`/api/notes/${fileName}/${type}`, { method: 'POST' });
    if (!res.ok) {
      const err = await res.json().catch(() => ({}));
      throw new Error(err.detail || `Action ${type} failed`);
    }
    return res.json();
  },

  async appendTasks(
    fileName: string,
    tasks: string
  ): Promise<{ status: string; message: string; detail?: string }> {
    const res = await fetch(`/api/notes/${fileName}/append_tasks`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ tasks }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to append tasks');
    return data;
  },

  async generateWeeklyBrief(): Promise<{ status: string; note: Note; detail?: string }> {
    const res = await fetch('/api/weekly_brief');
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || 'Failed to generate weekly brief');
    return data;
  },
};

export const ingestApi = {
  async uploadFile(file: File): Promise<{ status: string; note?: Note; detail?: string }> {
    const formData = new FormData();
    formData.append('file', file);

    const response = await fetch('/api/upload', {
      method: 'POST',
      body: formData,
    });

    const data = await response.json();
    if (!response.ok) {
      throw new Error(data.detail || 'Upload failed');
    }
    return data;
  },

  async ingestUrl(url: string, isQueue: boolean): Promise<Response> {
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
    };

    if (isQueue) {
      headers['X-Queue'] = 'true';
      headers['X-Stream'] = 'false';
    } else {
      headers['X-Stream'] = 'true';
    }

    return fetch('/api/ingest', {
      method: 'POST',
      headers,
      body: JSON.stringify({ url }),
    });
  },
};

export const chatApi = {
  async sendMessage(
    message: string,
    sessionId?: string | null,
    noteContext?: string
  ): Promise<{ response: string; model: string; session_id: string; detail?: string }> {
    const res = await fetch('/api/chat', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        message,
        session_id: sessionId || undefined,
        note_context: noteContext || undefined,
      }),
    });
    const data = await res.json();
    if (!res.ok) {
      throw new Error(data.detail || data.error || 'Chat request failed');
    }
    return data;
  },

  async getChats(): Promise<{
    sessions: Array<{
      session_id: string;
      title: string;
      last_updated: string;
      message_count: number;
    }>;
  }> {
    const res = await fetch('/api/chats');
    if (!res.ok) throw new Error('Failed to fetch chat sessions');
    return res.json();
  },

  async getChatSession(sessionId: string): Promise<{
    session_id: string;
    messages: Array<{ query: string; response: string; timestamp: string }>;
  }> {
    const res = await fetch(`/api/chats/${sessionId}`);
    if (!res.ok) throw new Error(`Failed to load chat session ${sessionId}`);
    return res.json();
  },

  async promoteToWiki(
    title: string,
    content: string
  ): Promise<{ status: string; fileName: string; note: Note; detail?: string }> {
    const res = await fetch('/api/save_answer', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ title, content }),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.detail || data.error || 'Failed to promote to wiki');
    return data;
  },
};

export const systemApi = {
  async getStatus(): Promise<{
    active_tasks: OperationTask[];
    recent_tasks: OperationTask[];
  }> {
    const res = await fetch('/api/status');
    if (!res.ok) throw new Error('Failed to fetch system status');
    return res.json();
  },

  async getConfig(): Promise<{ model?: string; inbox_mode?: boolean }> {
    const res = await fetch('/api/config');
    if (!res.ok) throw new Error('Failed to fetch system config');
    return res.json();
  },

  async syncVault(): Promise<{ status: string }> {
    const res = await fetch('/api/sync', { method: 'POST' });
    if (!res.ok) throw new Error('Failed to sync vault');
    return res.json();
  },
};
