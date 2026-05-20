---
type: youtube-video
date: 2026-05-20
author: LearnThatStack
url: https://youtu.be/Ala6PHlYjmw
category: General
tags: ['#tech/developer', '#tech/software-engineering', '#tools/git', '#productivity/workflows']
content_hash: c77db377408390108754c706e698bbee
transcript_status: complete
ai_model: models/gemini-2.5-flash-lite
processor: 
---
# General by LearnThatStack

> **AI Summary:** This content explains the fundamental concepts of Git, including commits, branches, HEAD, the staging area, and the differences between checkout, reset, revert, and rebase. It aims to demystify Git for developers to prevent fear and confusion during troubleshooting.

## Extracted Content
## Understanding Git: Commits, Branches, and More

This content aims to demystify [[Git]] for developers by explaining its core mechanics in detail.

*   **Core Concepts:** Git is presented as a database where the fundamental unit is a commit, which is a snapshot of the entire project at a specific moment. Branches are explained as simple pointers (sticky notes) to commits, and HEAD indicates the current location.
*   **Key Operations:** The differences between `checkout` (moving HEAD), `reset` (moving branches), and `revert` (creating corrective commits) are clarified, emphasizing their impact on different areas (working directory, staging area, repository).
*   **Advanced Topics & Recovery:** The video delves into the mechanics of `rebase`, explaining how it creates new commits rather than moving existing ones, and highlights the dangers of rebasing shared history. It also introduces `git reflog` as a safety net to recover "lost" commits by tracking HEAD's recent movements.

### Timestamps:

*   00:00 - Intro
*   00:33 - What is a commit?
*   01:45 - The DAG
*   03:03 - Branches
*   04:13 - HEAD
*   05:41 - The Staging Area — Git's waiting room
*   06:28 - Checkout vs Reset vs Revert
*   09:58 - Why rebase "rewrites history"
*   11:51 - The Reflog — your safety net
*   12:40 - Outro

### Resources:

*   [[Git]] Documentation: https://git-scm.com/doc
*   Pro [[Git]] Book (free): https://git-scm.com/book

## Raw Transcript
You use Git every single day. Commit, push, pull. It works until it doesn't. And then you're googling how to undo git rebase at 11 p.m. Mass copying commands from Stack Overflow, praying you don't make it worse. And an uncomfortable truth is many experienced developers don't actually understand Git. They memorize commands, but they don't know what's happening underneath. In next few minutes, let's understand Git better and never fear it again. Let's start from zero. Forget everything you think you know. Git is a database and the fundamental unit of that database is the commit. So what is a commit? It's a snapshot, a complete photograph of your entire project at one moment in time. Not the changes you made, the entire state of every file. Each commit contains three things. One, a pointer to that complete snapshot, every file exactly as it existed. Two, metadata, who created it, when, and the commit message. Three, a pointer to the parent commit, the commit that came directly before. When you make a new commit, get saves the full state of your project and links it back to where you were. This creates a chain. Each commit points to its parent. Parents point to their parents all the way back to the very first commit. That first commit, it's special. It has no parent. It's the origin point of your project history. And later, when you merge branches, you'll create commits with two parents. But we'll get there. For now, remember, commits point backwards, always backwards. Children know their parents, but parents never know their future children. If everyone just committed one after another, you'd have a straight line. Simple history. But real development is messier. You branch off for a feature. A colleague branches for a bug fix. Now you have commits sharing the same parent but going different directions. Then you merge. Now you have a commit with two parents. This structure has a name, a DAG, directed asylic graph. Sounds intimidating. It's not. Think of it like a family tree. Directed means relationships only go one way. Children point to parents. Never the reverse. A cyclic means no loops. Nobody can be their own grandparent. You can't create a cycle in history. Graph just means it's nodes and connections, commits and the links between them. This graph is your project's history. Every branch, every merge, every decision any developer ever made captured in the structure. And here's what makes Git powerful. Because every commit is a complete snapshot. You can jump to any point in this graph and see your project exactly as it existed. No reconstruction, no playing back changes, just there. Now, this graph can get complex. How do we navigate it? How does Git know which commits matter? That's where branches come in. And they're simpler than you'd believe. When learning Git, people usually assume branches as these heavy complex things, a whole separate copy of the codebase is completely wrong. A branch is just a sticky note, a pointer, a tiny text file that contains one piece of information, the hash of a commit. That's it. When you create a new branch called feature login, get creates a small file that says this branch points to commit A1 B23. Nothing more. Look at this graph. See these branches? They're just labels stuck on different commits. The commits themselves have no idea what branches exist. Branches don't contain commits. They point at them. When you make a new commit while on a branch, get creates the new commit, pointing back to where you were, moves the sticky note forward to the new commit. That's branching. The entire concept. This is why creating a branch is instant. You're not copying anything. You're placing a sticky note. And what about main? Not special. Just another sticky note that by convention we've agreed is the primary line of work. So we have commits, we have branches pointing at commits. But how does Git know where you are, what you're working on? Meet head. [snorts] Head is Git's way of tracking your location. It's another pointer, but usually instead of pointing out a commit, it points at a branch. When you're on the main branch, head points to main. Main points to a commit. That's your current location. Run get checkout feature and head moves to point at the feature branch. You're now working on that branch. But here's a situation that confuses people. What if you check out a specific commit, not a branch, a raw commit hash? Now head points directly to that commit. No branch in between. Get calls this detached head state. Sounds scary. It's not. If you understand it, here's what happens. You can still work. You can still commit, but no branch is following along. When you switch away, those commits are orphaned. No branch points to them. They're floating in space. Eventually, gets garbage collection will clean them up. You may have seen the situation. A developer checked out an old commit to test something, found a bug while there, fixed it, committed the fix, then ran git checkout main to merge their fix. The fix vanished. It was never on a branch. They couldn't find it. It was orphaned, then garbage collected. Two hours of work gone. This is why Git warns you, not because you're broken, but because anything you commit won't be saved unless you create a branch to hold it. Before we talk about undoing things, we need to understand one more concept that confuses people. Git actually has three areas where your code can live. One, your working directory, the actual files on your disk, what you see in your code editor. Two, the staging area, also known as the index, a waiting room where you prepare what will go into your next commit. Three, the repository, the database of commits, the permanent history. When you edit a file, it changes in your working directory. Git notices but doesn't care yet. When you run git add, you're moving those changes to the staging area. I want this in my next commit. When you run git commit, git takes everything in staging and creates a commit permanent history. Why does this matter? Because the commands we're about to discuss manipulate these layers differently. Understanding the three layers is the key to understanding reset. Three commands. They all seem to undo things, but they do completely different operations, and confusing them can cost you work. Let's go one by one. Checkout moves head. That's its job. Get checkout main now points head now points to main. Get checkout C1 head now points directly to that commit. Your working directory updates to match that commit snapshot. But, and this is important, no commits change. No branches move. History is untouched. You're just looking around. Safe, non-destructive, just moving your viewpoint. Now, let's talk about something more dangerous. Reset moves a branch. When you're on main and run get reset C1, you're saying move main to point at this commit. The commits that were ahead still exist in the database, but orphaned. No branch pointing to them. Now, here's where reset gets nuanced. It has three modes, and each one affects the three areas differently. Soft reset moves the branch. Staging area unchanged. Working directory unchanged. Your undone changes appear staged and ready to commit again. When to use it? You made three commits but want to combine them into one. Soft reset then recommit. Mixed reset the default moves the branch staging area reset to match the target commit. Your changes still exist in your files, just unstaged. When to use it? You committed something but want to restage it differently. Maybe split it into multiple commits. Hard reset moves the branch. Staging area reset. Working directory reset. Your files change. Uncommitted work gone from your disk. I have watched developers lose days of work because they ran gitreset. thinking they could undo it. You can't. Not easily. The orphan commits recoverable for a while if you know get secrets, but your uncommitted changes. The stuff you never committed, gone forever. When to use it? You want to completely abandon work and start fresh. You're sure. Revert takes a completely different philosophy. It doesn't move anything. It doesn't abandon anything. Revert creates a new commit that does the opposite of an old commit. Commit C added 50 lines. Get revert C creates commit D that removes those same 50 lines. History is preserved. The original commit still exists. You've just recorded we decided to undo what we did earlier. When to use it? You need to undo something that's already been pushed and shared. You can't rewrite shared history, but you can add to it. Quick summary. Checkout only moved head is safe. Exploring history. Reset moves branch and potentially working directory can be risky. Reshape local work. Revert. Nothing moves. New commit created is safe to undo shared history. Finally, the command that confuses most junior developers. Rebase. Let's set the scene. You created a feature branch from Maine. You made commits B and C. Meanwhile, Maine moved forward with commits X and Y. You have two options to integrate. Option one, merge. Create a merge commit with two parents. History shows the truth. Two parallel lines of work that join together. Option two, rebase. Take your commits and replay them on top of the new main. But you must understand this. A commit's identity is its hash. That hash is generated from the content, the metadata, and the parent pointer. Change any of those, including the parent, and you get a completely different hash, a different commit. Git can't move commits. That's not a thing. So what rebase actually does is look at commit B, calculate the changes it introduced, create a new commit B1 with those same changes, but with Y as its parent instead of the original base. Look at commit C, calculate its changes, create a new commit C1 with those changes sitting on top of B1. Move your feature branch to point at C1. The old B and C orphaned. They'll eventually be garbage collected. This is what rebasing actually does. This is why you never rebase commits that others have seen. If your colleague has the old commits and you push new commits with the same content but different hashes, Git sees them as completely unrelated work. Merging becomes a nightmare. Duplicate changes appear. Conflicts explode. But on local branches that you haven't shared, rebase is powerful. It keeps history linear and clean. Just know the trade-off. You're choosing a clean story over the messy truth. One last thing before we go. You've made a mistake. You reset hard. You rebased wrong. Commits are gone. Run get ref log. The ref log shows everywhere head has pointed recently. Every checkout, every commit, every reset. Those lost commits from your reset, the old commits before you rebased, they're probably still here. Find the hash. create a branch pointing to it and you've recovered your work. Git almost never truly deletes anything immediately. It just hides things. The ref log is your map. One caveat, ref log entries expire usually 90 days for reachable commits, 30 for unreachable, so don't wait months. But if disaster struck 5 minutes ago, you're probably fine. Let's step back. Git is a database of snapshots. Commits point to parents forming a graph. Branches and head are just pointers. Sticky notes telling Git what matters and where you are. Checkout moves your view. Reset moves branches. Revert adds corrective history. Rebase replays commits with new parents. And when everything goes wrong, ref log. The next time something breaks, you won't be copying Stack Overflow commands and praying. You'll be thinking in graphs and pointers. You'll know exactly what happened and exactly how to fix it. Don't forget to like and share if you found this helpful. Thanks for watching. See you in the next one.


---
### Original Caption
* How Git Actually Works — finally understand commits, branches, reset, rebase & more.

You use Git every day. Commit. Push. Pull. But when something breaks, you're Googling "how to undo git rebase", copying Stack Overflow commands and confused.

This video helps you understand git better. We'll open the black box and show you exactly how Git works underneath — so you never fear it again.

TIMESTAMPS:
00:00 - Intro
00:33 - What is a commit?
01:45 - The DAG
03:03 - Branches
04:13 - HEAD
05:41 - The Staging Area — Git's waiting room
06:28 - Checkout vs Reset vs Revert
09:58 - Why rebase "rewrites history"
11:51 - The Reflog — your safety net
12:40 - Outro

WHAT YOU'LL LEARN:
→ What a commit actually contains
→ Why branches are just tiny pointers — and why that matters
→ The difference between checkout, reset, and revert
→ When to use rebase vs merge (and why rebase can be dangerous)
→ How to recover "lost" commits with git reflog

Explore more such videos -
https://www.youtube.com/playlist?list=PLWP-VtjCVpWx7kPq30XRN6O6LjVQ4VL95

🔗 RESOURCES:
Git Documentation: https://git-scm.com/doc
Pro Git Book (free): https://git-scm.com/book

#git #gittutorial #gitforbeginners #programming #coding #developer #softwareengineering #learntocode #gitrebase #gitreset #computerscience #devtools #tech #webdevelopment
