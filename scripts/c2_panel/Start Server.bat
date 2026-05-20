@echo off
title C2 Server Controller
echo Booting C2 Node System...
start "" "http://localhost:3000"
node server.js
pause
