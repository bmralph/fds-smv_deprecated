set intelbin=c:\bin

call %intelbin%\ifortvars ia32

Rem erase *.obj
Rem erase *.mod
ifort -o fds2ascii ..\Data_Processing\fds2ascii.f90
pause