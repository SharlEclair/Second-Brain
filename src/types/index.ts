/**
 * Centralized TypeScript type definitions for Second Brain Web.
 */

export interface Note {
  title: string;
  fileName: string;
  date: string;
  source?: string;
  category?: string;
  url?: string;
  tags?: string[];
  ai_model?: string;
}

export interface ChatMessage {
  id: string;
  text: string;
  isAi: boolean;
  timestamp: Date;
}

export interface OperationTask {
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

export interface ActionResult {
  type: string;
  content: string;
}

export type NoteActionType = 'summarize' | 'deep_dive' | 'extract_tasks';

export type Theme = 'light' | 'dark';
