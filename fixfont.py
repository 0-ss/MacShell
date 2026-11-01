#!/usr/bin/env python3
"""Removes the "Binding loop detected for property font.family" warnings.

Cause: font.family: Fonts.forWeight(font.weight, fam)  reads the same Text's own font.weight while it writes font.family.
Fix:   each call reads the weight that Text declares explicitly (Font.Normal when it declares none).

Usage:  cd ~/.config/quickshell/MacShell && python3 fixfont.py [--dry]
Safe to re-run (it only touches the old pattern). Keeps a copy of every changed file next to it as <name>.qml.bak
"""
import os,shutil
import re,sys,glob
pat=re.compile(r'((?:Fonts\.|root\.)?[fF]ontForWeight|Fonts\.forWeight)\(\s*font\.weight\s*,')
def strip_strings(t):
    # blank out string literals and comments so braces inside them don't count (keep length)
    out=list(t); i=0; n=len(t)
    while i<n:
        c=t[i]
        if c in '"\'':
            q=c; j=i+1
            while j<n and t[j]!=q and t[j]!='\n':
                if t[j]=='\\': j+=1
                j+=1
            for k in range(i+1,min(j,n)): out[k]=' '
            i=j+1
        elif t.startswith('//',i):
            j=t.find('\n',i); j=n if j<0 else j
            for k in range(i,j): out[k]=' '
            i=j
        elif t.startswith('/*',i):
            j=t.find('*/',i); j=n if j<0 else j+2
            for k in range(i,j):
                if out[k]!='\n': out[k]=' '
            i=j
        else: i+=1
    return ''.join(out)
def value_at(t,pos):
    d=0;j=pos;n=len(t);q=None
    while j<n:
        c=t[j]
        if q:
            if c=='\\': j+=1
            elif c==q: q=None
        elif c in '"\'': q=c
        elif c in '([{': d+=1
        elif c in ')]}':
            if d==0: break
            d-=1
        elif d==0 and (c==';' or c=='\n'): break
        j+=1
    return t[pos:j].strip()
tot=0;unk=[];dyn=[]
for f in sorted(glob.glob('*.qml')):
    s=open(f).read()
    if not pat.search(s): continue
    c=strip_strings(s)
    edits=[]
    for m in pat.finditer(s):
        p=m.start(); d=0; i=p-1
        while i>=0:
            if c[i]=='}': d+=1
            elif c[i]=='{':
                if d==0: break
                d-=1
            i-=1
        start=i
        d=0; j=start+1
        while j<len(c):
            if c[j]=='{': d+=1
            elif c[j]=='}':
                if d==0: break
                d-=1
            j+=1
        end=j
        # mask nested blocks
        body=list(c[start+1:end]); d=0
        for k,ch in enumerate(body):
            if ch=='{': d+=1
            elif ch=='}': d-=1; body[k]=' ' if d>=0 else ch; 
            elif d>0 and ch!='\n': body[k]=' '
        body=''.join(body)
        mw=re.search(r'font\.weight\s*:\s*',body)
        mb=re.search(r'font\.bold\s*:\s*',body)
        if mw:
            v=value_at(s,start+1+mw.end())
            if 'font.' in v: unk.append((f,s.count('\n',0,p)+1,v)); continue
            repl='('+v+')' if re.search(r'[?:&|]',v) else v
        elif mb:
            v=value_at(s,start+1+mb.end())
            if 'font.' in v: unk.append((f,s.count('\n',0,p)+1,v)); continue
            repl='Font.Bold' if v=='true' else ('Font.Normal' if v=='false' else '(('+v+') ? Font.Bold : Font.Normal)')
        else: repl='Font.Normal'
        if re.search(r'[?:&|]',repl): dyn.append((f,s.count('\n',0,p)+1,repl))
        a=m.end()-len(m.group(0))+m.group(0).index('font.weight')
        edits.append((a,a+len('font.weight'),repl))
    for a,b,r in sorted(edits,reverse=True): s=s[:a]+r+s[b:]
    tot+=len(edits)
    if edits and '--dry' not in sys.argv:
        shutil.copy2(f,f+'.bak'); open(f,'w').write(s)
print('replaced',tot,'font.family bindings' + (' (dry run, nothing written)' if '--dry' in sys.argv else '')); print('UNRESOLVED',unk); print('DYNAMIC',dyn)
