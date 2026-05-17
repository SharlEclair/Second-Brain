import React, { useEffect, useState } from 'react';
import { Sparkles } from 'lucide-react';

interface Suggestion {
  title: string;
  fileName: string;
  category?: string;
}

interface SuggestionsWidgetProps {
  onSelectSuggestion: (note: any) => void;
}

export default function SuggestionsWidget({ onSelectSuggestion }: SuggestionsWidgetProps) {
  const [suggestions, setSuggestions] = useState<Suggestion[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchSuggestions();
  }, []);

  const fetchSuggestions = async () => {
    try {
      const res = await fetch('/api/suggestions');
      const data = await res.json();
      setSuggestions(data || []);
    } catch (e) {
      console.error('Failed to fetch suggestions', e);
    } finally {
      setLoading(false);
    }
  };

  if (loading) return null;
  if (suggestions.length === 0) return null;

  return (
    <div className="bg-black border border-slate-800 rounded-sm overflow-hidden">
      <div className="p-4 border-b border-slate-800 flex items-center justify-between bg-blue-500/5">
        <div className="flex items-center gap-2">
          <Sparkles className="w-4 h-4 text-blue-400" />
          <h3 className="text-xs uppercase tracking-widest font-bold text-slate-300">Rediscover</h3>
        </div>
        <button onClick={fetchSuggestions} className="text-[10px] text-slate-500 hover:text-white transition-colors">Refresh</button>
      </div>
      <div className="p-4 grid grid-cols-1 md:grid-cols-3 gap-4">
        {suggestions.map((suggestion, i) => (
          <button
            key={i}
            onClick={() => onSelectSuggestion(suggestion)}
            className="text-left p-4 border border-slate-800 bg-[#111] hover:border-blue-500/50 hover:bg-slate-900 transition-all rounded-sm flex flex-col justify-between group"
          >
            <h4 className="text-sm font-medium text-slate-300 line-clamp-2 leading-relaxed group-hover:text-blue-400 transition-colors">
              {suggestion.title}
            </h4>
            <div className="mt-4 text-[10px] text-slate-600 font-mono uppercase">
              {suggestion.category || "General"}
            </div>
          </button>
        ))}
      </div>
    </div>
  );
}
