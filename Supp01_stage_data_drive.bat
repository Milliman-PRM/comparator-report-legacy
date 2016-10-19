rem ### CODE OWNERS: Shea Parkes, Kyle Baird
rem
rem ### OBJECTIVE:
rem   Provide a convenience script to setup the data drive.
rem
rem ### DEVELOPER NOTES:
rem   It is not intended that this would be often utilized.
rem   Most of the time, the python script below will be ran automatically as part of PRM.
rem   However, during development, it might not already be ran, so this batch script provides
rem     a convenience method of running it.

SETLOCAL ENABLEDELAYEDEXPANSION

rem ### LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE

python "%~dp0\Post01_stage_data_drive.py"
