import { useState, useRef, useEffect, useCallback } from 'react';
import { ChatMessage, Note } from '../types';
import { chatApi } from '../services/api';

interface UseChatOptions {
  selectedNote?: Note | null;
  onError?: (msg: string) => void;
  onSuccess?: (msg: string) => void;
}

export function useChat(options: UseChatOptions = {}) {
  const optionsRef = useRef(options);
  optionsRef.current = options;

  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [chatInput, setChatInput] = useState('');
  const [currentSessionId, setCurrentSessionId] = useState<string | null>(null);
  const [isTyping, setIsTyping] = useState(false);
  const [isChatMinimized, setIsChatMinimized] = useState(false);
  const [useActiveNoteContext, setUseActiveNoteContext] = useState(false);
  const chatEndRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    if (chatEndRef.current) {
      chatEndRef.current.scrollIntoView({ behavior: 'smooth' });
    }
  }, [messages]);

  const loadChatSession = useCallback(async (sessionId: string) => {
    try {
      const data = await chatApi.getChatSession(sessionId);
      if (data.messages) {
        const loadedMessages: ChatMessage[] = [];
        data.messages.forEach((msg, index) => {
          loadedMessages.push({
            id: `user-${index}`,
            text: msg.query,
            isAi: false,
            timestamp: new Date(msg.timestamp),
          });
          loadedMessages.push({
            id: `ai-${index}`,
            text: msg.response,
            isAi: true,
            timestamp: new Date(msg.timestamp),
          });
        });
        setMessages(loadedMessages);
        setCurrentSessionId(sessionId);
      }
    } catch (e: any) {
      console.error('Failed to load chat session', e);
      optionsRef.current.onError?.(e.message || 'Failed to load chat session');
    }
  }, []);

  const handleNewSession = useCallback(() => {
    setCurrentSessionId(null);
    setMessages([]);
  }, []);

  const handleChat = useCallback(
    async (e: React.FormEvent) => {
      e.preventDefault();
      if (!chatInput.trim()) return;

      const userMsg: ChatMessage = {
        id: Date.now().toString(),
        text: chatInput,
        isAi: false,
        timestamp: new Date(),
      };

      setMessages((prev) => [...prev, userMsg]);
      setChatInput('');
      setIsTyping(true);

      try {
        const currentSelected = optionsRef.current.selectedNote;
        const noteContext =
          useActiveNoteContext && currentSelected ? currentSelected.fileName : undefined;
        const data = await chatApi.sendMessage(userMsg.text, currentSessionId, noteContext);

        if (data.response) {
          if (!currentSessionId && data.session_id) {
            setCurrentSessionId(data.session_id);
          }
          const aiMsg: ChatMessage = {
            id: (Date.now() + 1).toString(),
            text: data.response,
            isAi: true,
            timestamp: new Date(),
          };
          setMessages((prev) => [...prev, aiMsg]);
        } else {
          throw new Error('Unknown AI response error');
        }
      } catch (e: any) {
        console.error('Chat failed', e);
        optionsRef.current.onError?.(`Chat failed: ${e.message}`);
      } finally {
        setIsTyping(false);
      }
    },
    [chatInput, currentSessionId, useActiveNoteContext]
  );

  const handlePromoteToWiki = useCallback(async (msg: ChatMessage) => {
    const title = prompt('Enter a title for this new Synthesis note:');
    if (!title) return;
    try {
      const data = await chatApi.promoteToWiki(title, msg.text);
      if (data.status === 'success') {
        optionsRef.current.onSuccess?.('Synthesized into Wiki: ' + data.fileName);
      } else {
        optionsRef.current.onError?.('Failed to promote: ' + (data.detail || 'Unknown error'));
      }
    } catch (e: any) {
      optionsRef.current.onError?.('Error: ' + e.message);
    }
  }, []);

  return {
    messages,
    setMessages,
    chatInput,
    setChatInput,
    currentSessionId,
    setCurrentSessionId,
    isTyping,
    isChatMinimized,
    setIsChatMinimized,
    useActiveNoteContext,
    setUseActiveNoteContext,
    chatEndRef,
    handleChat,
    loadChatSession,
    handleNewSession,
    handlePromoteToWiki,
  };
}
