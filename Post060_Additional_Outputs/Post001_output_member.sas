/*
### CODE OWNERS: Jack Leemhuis, Jason Altieri

### OBJECTIVE:
	Per client request, output the member table from 035_Staging_Membership to the comparator report deliverable.
	This includes in the NewYorkMillimanShare data directory and the postboarding 050_Wrap_Up data directory.

### DEVELOPER NOTES:
	<none>
*/

/****** SAS SPECIFIC HEADER SECTION *****/
options sasautos = ("S:\MISC\_IndyMacros\Code\General Routines" sasautos) compress = yes;
%include "%sysget(UserProfile)\HealthBI_LocalData\Supp01_Parser.sas" / source2;
%include "&path_project_data.postboarding\postboarding_libraries.sas" / source2;
%include "%GetParentFolder(1)share01_postboarding.sas" / source2;

libname M035_Out "&M035_Out." access=readonly;
libname post060 "&post060.";

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

/**** LIBRARIES, LOCATIONS, LITERALS, ETC. GO ABOVE HERE ****/

/*Output member table to postboarding 050_Wrap_Up data directory*/

data Post060.Member;
	format name_client $256.;
	set M035_Out.Member;
	&assign_name_client.;
run;

/*Output member table to NewYorkMillimanShare data directory*/

data NYMS.Member;
	format name_client $256.;
	set M035_Out.Member;
	&assign_name_client.;
run;

%put System Return Code = &syscc.;
