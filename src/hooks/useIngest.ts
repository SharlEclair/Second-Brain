import { useState, useRef, useEffect, useCallback } from 'react';
import { Note } from '../types';
import { ingestApi } from '../services/api';

interface UseIngestOptions {
  onNoteIngested?: (note: Note) => void;
  onRefreshNotes?: () => Promise<void>;
  onRefreshStatus?: () => Promise<void>;
}

export function useIngest(options: UseIngestOptions = {}) {
  const optionsRef = useRef(options);
  optionsRef.current = options;

  const [url, setUrl] = useState('');
  const [loadingNote, setLoadingNote] = useState(false);
  const [ingestStatus, setIngestStatus] = useState<string | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [success, setSuccess] = useState<string | null>(null);
  const [isDragging, setIsDragging] = useState(false);
  const [isRecording, setIsRecording] = useState(false);
  const [mediaRecorder, setMediaRecorder] = useState<MediaRecorder | null>(null);

  const fileInputRef = useRef<HTMLInputElement>(null);

  // Global clipboard paste handler
  useEffect(() => {
    const handleGlobalPaste = (e: ClipboardEvent) => {
      const target = e.target as HTMLElement;
      if (target.tagName === 'INPUT' || target.tagName === 'TEXTAREA') return;

      const pastedText = e.clipboardData?.getData('text');
      if (pastedText && pastedText.startsWith('http')) {
        setUrl(pastedText);
        setTimeout(() => {
          const form = document.querySelector('form');
          if (form) form.dispatchEvent(new Event('submit', { cancelable: true, bubbles: true }));
        }, 50);
      }
    };

    window.addEventListener('paste', handleGlobalPaste);
    return () => window.removeEventListener('paste', handleGlobalPaste);
  }, []);

  const uploadFileObj = useCallback(async (file: File) => {
    setLoadingNote(true);
    setError(null);
    setSuccess(null);
    setIngestStatus(`Uploading ${file.name}...`);

    try {
      const data = await ingestApi.uploadFile(file);
      setSuccess('File successfully ingested');
      setTimeout(() => setSuccess(null), 3000);
      await optionsRef.current.onRefreshNotes?.();
      setUrl('');
      if (data.note) {
        optionsRef.current.onNoteIngested?.(data.note);
      }
    } catch (err: any) {
      setError(err.message || 'Failed to process file.');
    } finally {
      setLoadingNote(false);
      setIngestStatus(null);
      if (fileInputRef.current) {
        fileInputRef.current.value = '';
      }
    }
  }, []);

  const handleFileUpload = useCallback(
    async (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (!file) return;
      await uploadFileObj(file);
    },
    [uploadFileObj]
  );

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault();
    setIsDragging(true);
  }, []);

  const handleDragLeave = useCallback(() => {
    setIsDragging(false);
  }, []);

  const handleDrop = useCallback(
    async (e: React.DragEvent) => {
      e.preventDefault();
      setIsDragging(false);

      const file = e.dataTransfer.files?.[0];
      if (!file) return;
      await uploadFileObj(file);
    },
    [uploadFileObj]
  );

  const startRecording = useCallback(async () => {
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
        const file = new File([audioBlob], `voice_capture_${Date.now()}.wav`, {
          type: 'audio/wav',
        });
        await uploadFileObj(file);
        stream.getTracks().forEach((track) => track.stop());
      };

      recorder.start();
      setMediaRecorder(recorder);
      setIsRecording(true);
    } catch (err) {
      console.error('Failed to start voice recording', err);
      setError('Failed to access microphone.');
    }
  }, [uploadFileObj]);

  const stopRecording = useCallback(() => {
    if (mediaRecorder && isRecording) {
      mediaRecorder.stop();
      setIsRecording(false);
      setMediaRecorder(null);
    }
  }, [mediaRecorder, isRecording]);

  const toggleRecording = useCallback(() => {
    if (isRecording) {
      stopRecording();
    } else {
      startRecording();
    }
  }, [isRecording, startRecording, stopRecording]);

  const handleIngest = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!url) return;

      setLoadingNote(true);
      setError(null);
      setSuccess(null);
      setIngestStatus('Initiating session...');

      try {
        const isQueue = url.includes('twitter.com') || url.includes('x.com');
        const response = await ingestApi.ingestUrl(url, isQueue);

        if (isQueue) {
          const data = await response.json();
          setSuccess(data.message || 'Added to background queue');
          setTimeout(() => setSuccess(null), 3000);
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
              await optionsRef.current.onRefreshNotes?.();
              await optionsRef.current.onRefreshStatus?.();
              if (data.note) {
                optionsRef.current.onNoteIngested?.(data.note);
              }
              setUrl('');
              setSuccess(
                data.status === 'existing' ? 'Note already exists' : 'Note successfully ingested'
              );
              setTimeout(() => setSuccess(null), 3000);
            } else if (data.status === 'error') {
              setError(data.message);
            }
          }
        }
      } catch (e: any) {
        console.error('Ingestion failed', e);
        setError('Network error or server is down');
      } finally {
        setLoadingNote(false);
        setIngestStatus(null);
        optionsRef.current.onRefreshStatus?.();
      }
    },
    [url]
  );

  return {
    url,
    setUrl,
    loadingNote,
    setLoadingNote,
    ingestStatus,
    setIngestStatus,
    error,
    setError,
    success,
    setSuccess,
    isDragging,
    isRecording,
    fileInputRef,
    handleFileUpload,
    handleDragOver,
    handleDragLeave,
    handleDrop,
    toggleRecording,
    handleIngest,
  };
}
