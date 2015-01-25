Convert flac files to mp3 for transfer to mp3 player. Intended to be easy to use.

Creates a time-stamped output directory with no subdirectories.

Copies flac files from source to destination before conversion begins.

Uses ffmpeg or avconv. Dependencies must be installed.

Arguments are passed as KEY1=VALUE1 KEY2=VALUE2 and so on.

Step 1: flac files in dir structure D are copied to new working dir DN. Subdirectories of D will be scanned.
The subdirectory structure of D is *not* recreated.

Step 2: conversion is accomplished using forks (settable).

Step 3: after completion, flac files are deleted from DN.

