/*
### CODE OWNERS: Jason Altieri

### OBJECTIVE:
	Store code that is shared across programs in the module to limit
	duplication

### DEVELOPER NOTES:
	It is assumed that the IndyMacros and parser have been loaded.
*/

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

%let NYMS_pre = K:\PHI\0273NYP\NewYorkMillimanShare\&project_id.\&deliverable_name.\;
%GetFileNamesfromDir(&NYMS_pre.,comp_report_folders,);

proc sort data=comp_report_folders out=comp_report_folders_sort;
	by directory descending filename;
run;

data comp_report_folders_sort_dist;
	set comp_report_folders_sort;
	by directory descending filename;

	if first.directory then output;
run;

proc sql noprint;
	select filename
	into :recent_comp_folder trimmed
	from comp_report_folders_sort_dist
	;
quit;
%put &=recent_comp_folder.;

libname NYMS "&NYMS_pre.&recent_comp_folder.\";
