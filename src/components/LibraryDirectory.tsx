import React, { useState, useEffect } from 'react';
import { Book, Folder, ChevronRight, Loader2 } from 'lucide-react';
import { motion } from 'motion/react';

interface LibraryDirectoryProps {
  onSelectCategory: (categoryName: string) => void;
}

export const LibraryDirectory: React.FC<LibraryDirectoryProps> = ({ onSelectCategory }) => {
  const [categories, setCategories] = useState<{name: string, count: number}[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetch('/api/notes/_master-index.md')
      .then(res => res.text())
      .then(text => {
        const cats: {name: string, count: number}[] = [];
        const lines = text.split('\n');
        for (const line of lines) {
          // Parse lines like: - **[[Event/_index|Event]]**: 7 articles
          const match = line.match(/- \*\*\[\[.*?\|(.*?)\]\]\*\*: (\d+) articles/);
          if (match) {
            cats.push({ name: match[1], count: parseInt(match[2]) });
          }
        }
        setCategories(cats);
        setLoading(false);
      })
      .catch(err => {
        console.error("Failed to load master index", err);
        setLoading(false);
      });
  }, []);

  if (loading) {
    return (
      <div className="bg-[#0a0a0a] border border-slate-800 p-4 rounded-sm flex items-center justify-center min-h-[200px]">
        <Loader2 className="w-5 h-5 text-slate-700 animate-spin" />
      </div>
    );
  }

  return (
    <div className="bg-[#0a0a0a] border border-slate-800 p-4 rounded-sm flex flex-col h-full max-h-[300px]">
      <div className="flex items-center gap-2 mb-4 shrink-0">
        <Book className="w-4 h-4 text-orange-500" />
        <h4 className="text-[10px] font-mono uppercase tracking-widest text-slate-300">Library Directory</h4>
      </div>
      
      <div className="flex-1 overflow-y-auto space-y-1 pr-2 custom-scrollbar">
        {categories.length === 0 ? (
          <p className="text-xs text-slate-600 font-mono italic">No topics indexed yet.</p>
        ) : (
          categories.map((cat, i) => (
            <motion.button
              initial={{ opacity: 0, x: -10 }}
              animate={{ opacity: 1, x: 0 }}
              transition={{ delay: i * 0.05 }}
              key={cat.name}
              onClick={() => onSelectCategory(cat.name + "/_index.md")}
              className="w-full flex items-center justify-between p-2 hover:bg-slate-900 border border-transparent hover:border-slate-800 rounded-sm transition-all group text-left"
            >
              <div className="flex items-center gap-3">
                <Folder className="w-3.5 h-3.5 text-slate-600 group-hover:text-orange-400 transition-colors" />
                <span className="text-xs font-mono text-slate-400 group-hover:text-slate-200">{cat.name}</span>
              </div>
              <div className="flex items-center gap-2">
                <span className="text-[9px] font-mono bg-black px-1.5 py-0.5 rounded text-slate-500 group-hover:text-orange-500/70 border border-slate-800">
                  {cat.count}
                </span>
                <ChevronRight className="w-3 h-3 text-slate-700 group-hover:text-orange-500 transition-colors" />
              </div>
            </motion.button>
          ))
        )}
      </div>
    </div>
  );
};
