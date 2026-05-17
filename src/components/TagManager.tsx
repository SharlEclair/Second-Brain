import React, { useEffect, useState } from 'react';
import { Tag, Edit2, Check, X, Loader2 } from 'lucide-react';

export default function TagManager() {
  const [tags, setTags] = useState<string[]>([]);
  const [loading, setLoading] = useState(true);
  const [editingTag, setEditingTag] = useState<string | null>(null);
  const [editValue, setEditValue] = useState('');
  const [actionLoading, setActionLoading] = useState(false);

  useEffect(() => {
    fetchTags();
  }, []);

  const fetchTags = async () => {
    try {
      const res = await fetch('/api/tags');
      const data = await res.json();
      setTags(data.tags || []);
    } catch (e) {
      console.error('Failed to fetch tags', e);
    } finally {
      setLoading(false);
    }
  };

  const handleSaveRename = async (oldTag: string) => {
    if (!editValue || editValue === oldTag) {
      setEditingTag(null);
      return;
    }

    setActionLoading(true);
    try {
      await fetch('/api/tags/rename', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ old_tag: oldTag, new_tag: editValue })
      });
      await fetchTags();
    } catch (e) {
      console.error('Failed to rename tag', e);
    } finally {
      setActionLoading(false);
      setEditingTag(null);
    }
  };

  if (loading) {
    return <div className="p-4 text-slate-500 text-xs text-center font-mono animate-pulse">Loading tags...</div>;
  }

  return (
    <div className="bg-[#0a0a0a] border border-white/5 rounded-sm overflow-hidden">
      <div className="p-4 border-b border-white/5 flex items-center gap-2 bg-black/20">
        <Tag className="w-4 h-4 text-emerald-400" />
        <h3 className="text-xs font-mono uppercase tracking-widest text-zinc-300">Vault Tags</h3>
      </div>
      <div className="p-4 max-h-[300px] overflow-y-auto">
        <div className="flex flex-wrap gap-2">
          {tags.map((tag, i) => (
            <div key={i} className="flex items-center">
              {editingTag === tag ? (
                <div className="flex items-center gap-1 bg-slate-900 border border-emerald-500/50 rounded-sm px-2 py-1">
                  <input
                    type="text"
                    value={editValue}
                    onChange={(e) => setEditValue(e.target.value)}
                    className="bg-transparent text-xs font-mono text-white outline-none w-24"
                    autoFocus
                    disabled={actionLoading}
                    onKeyDown={(e) => e.key === 'Enter' && handleSaveRename(tag)}
                  />
                  <button onClick={() => handleSaveRename(tag)} disabled={actionLoading} className="text-emerald-500 hover:text-emerald-400">
                    {actionLoading ? <Loader2 className="w-3 h-3 animate-spin" /> : <Check className="w-3 h-3" />}
                  </button>
                  <button onClick={() => setEditingTag(null)} disabled={actionLoading} className="text-slate-500 hover:text-red-400">
                    <X className="w-3 h-3" />
                  </button>
                </div>
              ) : (
                <div className="group flex items-center gap-2 bg-slate-900/50 border border-slate-800 rounded-sm px-2 py-1 hover:border-slate-700 transition-colors">
                  <span className="text-xs font-mono text-slate-300">#{tag}</span>
                  <button
                    onClick={() => {
                      setEditingTag(tag);
                      setEditValue(tag);
                    }}
                    className="opacity-0 group-hover:opacity-100 text-slate-500 hover:text-white transition-all"
                  >
                    <Edit2 className="w-3 h-3" />
                  </button>
                </div>
              )}
            </div>
          ))}
          {tags.length === 0 && <span className="text-xs text-slate-500 font-mono">No tags found.</span>}
        </div>
      </div>
    </div>
  );
}
