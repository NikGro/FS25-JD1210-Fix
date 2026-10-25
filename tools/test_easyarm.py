#!/usr/bin/env python3
"""Offline test of scripts/JDEasyArmControl.lua with a mocked crane (geometry from 1210G.i3d)."""
import os
from lupa import lua51, luajit21

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = os.path.join(HERE, '..', 'FS25_JD_1210G_Improved', 'scripts', 'JDEasyArmControl.lua')
src = open(SCRIPT, encoding='utf-8').read()
for mod, label in ((lua51, 'Lua 5.1'), (luajit21, 'LuaJIT')):
    r = mod.LuaRuntime().eval('function(s) local f,e=loadstring(s) return f and "OK" or e end')(src)
    assert r == 'OK', f'{label}: {r}'
print('syntax OK')

L = lua51.LuaRuntime()
L.execute(open(os.path.join(HERE, 'mock_crane.lua')).read())
L.execute('g_currentModName = "FS25_JD_1210G_Improved"')
L.execute(src)
L.execute(open(os.path.join(HERE, 'test_easyarm.lua')).read())
print('ALL TESTS OK')
