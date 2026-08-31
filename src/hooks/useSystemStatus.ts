import { useState, useEffect, useCallback } from 'react';
import { OperationTask, Theme } from '../types';
import { systemApi } from '../services/api';

export function useSystemStatus() {
  const [activeTasks, setActiveTasks] = useState<OperationTask[]>([]);
  const [recentTasks, setRecentTasks] = useState<OperationTask[]>([]);
  const [activeModel, setActiveModel] = useState('GEMINI-2.5-FLASH-LITE');
  const [isSyncing, setIsSyncing] = useState(false);
  const [showDashboard, setShowDashboard] = useState(false);

  const [theme, setTheme] = useState<Theme>(() => {
    const saved = localStorage.getItem('theme');
    if (saved === 'light' || saved === 'dark') return saved;
    return 'dark';
  });

  useEffect(() => {
    localStorage.setItem('theme', theme);
    if (theme === 'light') {
      document.documentElement.classList.add('light');
    } else {
      document.documentElement.classList.remove('light');
    }
  }, [theme]);

  const toggleTheme = useCallback(() => {
    setTheme((prev) => (prev === 'light' ? 'dark' : 'light'));
  }, []);

  const fetchOperationStatus = useCallback(async () => {
    try {
      const data = await systemApi.getStatus();
      setActiveTasks(data.active_tasks || []);
      setRecentTasks(data.recent_tasks || []);
    } catch (e) {
      console.error('Failed to fetch operation status', e);
    }
  }, []);

  const fetchConfig = useCallback(async () => {
    try {
      const d = await systemApi.getConfig();
      if (d.model) {
        setActiveModel(d.model.replace('models/', '').toUpperCase());
      }
    } catch {
      // ignore
    }
  }, []);

  const handleSync = useCallback(async () => {
    setIsSyncing(true);
    try {
      await systemApi.syncVault();
      await new Promise((r) => setTimeout(r, 2000));
    } catch (e) {
      console.error('Sync failed', e);
    } finally {
      setIsSyncing(false);
    }
  }, []);

  useEffect(() => {
    fetchOperationStatus();
    fetchConfig();
    const interval = setInterval(fetchOperationStatus, 2000);
    return () => clearInterval(interval);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const visibleTask = activeTasks[0] || recentTasks.find((task) => task.state === 'failed');
  const visibleTaskProgress =
    typeof visibleTask?.progress === 'number' ? `${visibleTask.progress}%` : null;

  return {
    activeTasks,
    recentTasks,
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
  };
}
